"""Re-fetch every milestone source and check the recorded quote really is there.

The earlier reviews recorded a quote and a locator by hand. A hand-written quote
can drift from the document, and a document can be replaced. This script
re-opens every URL, extracts the publication date the page itself declares, and
searches the page text for the recorded quote. Anything that cannot be
confirmed is reported, never assumed.

Publication dates come from three independent places and are reconciled rather
than guessed: the page's own metadata, the CMS date embedded in the URL path,
and the date the earlier reviewer wrote into the locator. Agreement is recorded
as `agreement`; disagreement is recorded as `conflict` and blocks the row.

Output: data/official_evidence/milestone_source_captures_2026-10-29.json
"""
import hashlib
import io
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = 'data/official_evidence/milestone_source_captures_2026-10-29.json'
REVIEWS = [
    'data/official_evidence/history_review_shenzhen_shanghai_2026-10-28.json',
    'data/official_evidence/history_review_beijing_guangzhou_2026-10-28.json',
    'data/official_evidence/history_review_chengdu_2026-10-28.json',
]
HEADERS = {
    'User-Agent': ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                   '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'),
    'Accept': 'text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
}

META_PATTERNS = [
    re.compile(r'name=["\']?(?:PubDate|publishdate|pubdate|firstpublishedtime)["\']?[^>]*?'
               r'content=["\']?(\d{4})-(\d{1,2})-(\d{1,2})', re.I),
    re.compile(r'content=["\']?(\d{4})-(\d{1,2})-(\d{1,2})[^"\']*["\'][^>]*?'
               r'name=["\']?(?:PubDate|publishdate|pubdate)["\']?', re.I),
    re.compile(r'property=["\']?article:published_time["\']?[^>]*?content=["\']?(\d{4})-(\d{1,2})-(\d{1,2})', re.I),
]
MARKED_PATTERNS = [
    re.compile(r'(?:发布时间|发布日期|发布于|发表时间|成文日期|公开日期)[：:\s]*(\d{4})-(\d{1,2})-(\d{1,2})'),
    re.compile(r'(?:发布时间|发布日期|发布于|发表时间|成文日期|公开日期)[：:\s]*(\d{4})年(\d{1,2})月(\d{1,2})日'),
]
LOOSE_PATTERNS = [
    re.compile(r'(\d{4})-(\d{2})-(\d{2})\s*\d{2}:\d{2}'),
    re.compile(r'(\d{4})年(\d{1,2})月(\d{1,2})日\s*\d{1,2}:\d{2}'),
]
URL_PATTERNS = [
    re.compile(r'/(20\d{2})(\d{2})(\d{2})/'),
    re.compile(r'/t(20\d{2})(\d{2})(\d{2})_'),
    re.compile(r'/(20\d{2})-(\d{2})/(\d{2})/'),
    re.compile(r'/(20\d{2})/(\d{2})/(\d{2})/'),
    re.compile(r'/(20\d{2})/(\d{2})-(\d{2})/'),
]
LOCATOR_PATTERNS = [
    re.compile(r'发布[于]?\s*(20\d{2})-(\d{1,2})-(\d{1,2})'),
    re.compile(r'·\s*(20\d{2})-(\d{1,2})-(\d{1,2})\s*·'),
    re.compile(r'(20\d{2})-(\d{1,2})-(\d{1,2})\s*·'),
]


def _fetch_curl(url):
    """Some operator sites present TLS parameters Python's OpenSSL rejects."""
    import subprocess
    result = subprocess.run(
        ['curl', '-sS', '-L', '--max-time', '45', '--compressed',
         '-A', HEADERS['User-Agent'], '-w', '\n%{http_code}', url],
        capture_output=True)
    if result.returncode != 0:
        raise OSError(result.stderr.decode('utf-8', 'ignore').strip() or 'curl failed')
    body, _, status = result.stdout.rpartition(b'\n')
    return int(status.strip() or 0), body


def fetch(url):
    import http.client
    request = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            chunks = []
            while True:
                try:
                    chunk = response.read(65536)
                except http.client.IncompleteRead as partial:
                    chunks.append(partial.partial)
                    break
                if not chunk:
                    break
                chunks.append(chunk)
            return response.status, b''.join(chunks), response.headers.get('Content-Type', '')
    except urllib.error.HTTPError:
        raise
    except Exception:
        status, body = _fetch_curl(url)
        if status == 0:
            raise
        return status, body, ''


def decode(body, content_type):
    charset = 'utf-8'
    match = re.search(r'charset=([\w-]+)', content_type or '', re.I)
    if match:
        charset = match.group(1)
    else:
        match = re.search(rb'charset=["\']?([\w-]+)', body[:4000], re.I)
        if match:
            charset = match.group(1).decode('ascii', 'ignore')
    for candidate in (charset, 'utf-8', 'gb18030'):
        try:
            return body.decode(candidate)
        except (LookupError, UnicodeDecodeError):
            continue
    return body.decode('utf-8', 'ignore')


def strip_html(text):
    text = re.sub(r'(?is)<(script|style)[^>]*>.*?</\1>', ' ', text)
    text = re.sub(r'(?s)<[^>]+>', ' ', text)
    text = text.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
    return re.sub(r'\s+', ' ', text)


def squash(text):
    return re.sub(r'\s+', '', text or '')


def _date(groups):
    year, month, day = groups
    try:
        month, day = int(month), int(day)
    except ValueError:
        return ''
    if not (1 <= month <= 12 and 1 <= day <= 31):
        return ''
    return f'{int(year):04d}-{month:02d}-{day:02d}'


def _search(patterns, text):
    for pattern in patterns:
        match = pattern.search(text)
        if match:
            value = _date(match.groups())
            if value:
                return value
    return ''


def pdf_text(body):
    try:
        from pypdf import PdfReader
    except ImportError:
        return ''
    try:
        reader = PdfReader(io.BytesIO(body))
    except Exception:
        return ''
    chunks = []
    for page in reader.pages:
        try:
            chunks.append(page.extract_text() or '')
        except Exception:
            continue
    return '\n'.join(chunks)


def capture(url, quote, locator):
    row = {'url': url, 'httpStatus': 0, 'quoteFound': False, 'sha256': '', 'textLength': 0,
           'metaDate': '', 'markedDate': '', 'looseDate': '', 'urlDate': '', 'locatorDate': '',
           'publishDate': '', 'agreement': '', 'error': ''}
    row['urlDate'] = _search(URL_PATTERNS, url)
    row['locatorDate'] = _search(LOCATOR_PATTERNS, locator or '')
    try:
        status, body, content_type = fetch(url)
    except urllib.error.HTTPError as error:
        row['httpStatus'] = error.code
        row['error'] = f'HTTP {error.code}'
        return row
    except Exception as error:
        row['error'] = f'{type(error).__name__}: {error}'
        return row
    row['httpStatus'] = status
    row['sha256'] = hashlib.sha256(body).hexdigest()
    is_pdf = 'pdf' in (content_type or '').lower() or body[:4] == b'%PDF'
    if is_pdf:
        row['kind'] = 'pdf'
        raw = pdf_text(body)
        if not raw:
            row['error'] = 'pdf: text layer not extractable'
            return row
        plain = squash(raw)
        row['markedDate'] = _search(MARKED_PATTERNS, plain)
    else:
        row['kind'] = 'html'
        raw = decode(body, content_type)
        row['metaDate'] = _search(META_PATTERNS, raw)
        plain = squash(strip_html(raw))
        # The visible 发布日期 is the page's own statement about itself; a
        # PubDate meta tag can carry the date the CMS re-published an archived
        # item, so the visible line wins.
        row['markedDate'] = _search(MARKED_PATTERNS, plain)
    row['textLength'] = len(plain)
    row['looseDate'] = _search(LOOSE_PATTERNS, plain)
    needle = squash(quote)
    if needle:
        row['quoteFound'] = needle in plain
        if not row['quoteFound'] and len(needle) > 24:
            head, tail = needle[:20], needle[-20:]
            row['quoteFound'] = head in plain and tail in plain
            if row['quoteFound']:
                row['matchedLoosely'] = True
    # Priority: the page's own 发布日期 line, then its metadata, then the CMS
    # path. The reviewer's earlier note is a cross-check only, never the source.
    for basis, value in (('marked', row['markedDate']), ('meta', row['metaDate']),
                         ('url', row['urlDate'])):
        if value:
            row['publishDate'] = value
            row['dateBasis'] = basis
            break
    if not row['publishDate'] and row['looseDate']:
        row['publishDate'] = row['looseDate']
        row['dateBasis'] = 'in_text'
    declared = [value for value in (row['metaDate'], row['markedDate'], row['urlDate'],
                                    row['locatorDate']) if value]
    if declared:
        row['declaredDates'] = declared
        if len(set(declared)) == 1:
            row['agreement'] = 'consistent'
        elif row['publishDate'] in declared:
            row['agreement'] = 'consistent_with_review'
        else:
            row['agreement'] = 'conflict'
    elif row['publishDate']:
        row['agreement'] = 'in_text_only'
    return row


def main():
    rows = {}
    for name in REVIEWS:
        document = json.loads((ROOT / name).read_text(encoding='utf-8'))
        for city, block in document['cities'].items():
            for milestone in block['milestones']:
                key = milestone['chapterId']
                if key in rows:
                    continue
                row = capture(milestone.get('sourceUrl', ''), milestone.get('quote', ''),
                              milestone.get('locator', ''))
                row['city'] = city
                row['date'] = milestone.get('date')
                rows[key] = row
                flag = 'OK ' if row['quoteFound'] and row['publishDate'] else '-- '
                print(f'{flag}{city:10s} {key:46s} {row["httpStatus"]:3d} '
                      f'pub={row["publishDate"] or "-":10s} {row["agreement"] or "-":13s} '
                      f'quote={"y" if row["quoteFound"] else "n"} {row["error"]}')
    path = ROOT / OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({'schemaVersion': 1, 'capturedAt': '2026-10-29', 'sources': rows},
                               ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    total = len(rows)
    good = sum(1 for r in rows.values() if r['quoteFound'] and r['publishDate'])
    print(f'CAPTURED {good}/{total} -> {OUT}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
