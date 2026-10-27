"""Fetch a page once, then serve it from a local cache.

Re-reading the same official page a dozen times is slow and rude to the site,
and it makes a review run non-reproducible when a page is temporarily down. The
cache keys on the URL and keeps the raw bytes plus the extracted text, so a
rerun reads exactly what the first run read.
"""
import hashlib
import json
import re
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache/pages'
HEADERS = {
    'User-Agent': ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                   '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'),
    'Accept': 'text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
}


def _key(url):
    return hashlib.sha1(url.encode('utf-8')).hexdigest()


def _path(url):
    return CACHE / f'{_key(url)}.json'


def _fetch(url):
    import subprocess
    import urllib.request
    request = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            body = response.read()
            return response.status, body, response.headers.get('Content-Type', '')
    except urllib.error.HTTPError as error:
        return error.code, b'', ''
    except Exception:
        result = subprocess.run(
            ['curl', '-sS', '-L', '--max-time', '45', '--compressed', '--insecure',
             '-A', HEADERS['User-Agent'], '-w', '\n%{http_code}', url], capture_output=True)
        if result.returncode != 0:
            return 0, b'', ''
        body, _, status = result.stdout.rpartition(b'\n')
        return int(status.strip() or 0), body, ''


def _decode(body, content_type):
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
    text = (text.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<')
                .replace('&gt;', '>').replace('&quot;', '"').replace('&#39;', "'"))
    return re.sub(r'[ \t\u3000]+', ' ', text)


def _pdf_text(body):
    try:
        import io
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


def load(url, *, refresh=False):
    """Return `{status, contentType, html, text, cachedAt}` for a URL."""
    path = _path(url)
    if path.exists() and not refresh:
        return json.loads(path.read_text(encoding='utf-8'))
    status, body, content_type = _fetch(url)
    is_pdf = 'pdf' in (content_type or '').lower() or body[:4] == b'%PDF'
    if is_pdf:
        text = _pdf_text(body)
        html = ''
    else:
        html = _decode(body, content_type) if body else ''
        text = strip_html(html)
    row = {'url': url, 'status': status, 'contentType': content_type,
           'sha256': hashlib.sha256(body).hexdigest() if body else '',
           'bytes': len(body), 'html': html, 'text': text}
    CACHE.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(row, ensure_ascii=False), encoding='utf-8')
    return row


if __name__ == '__main__':
    import sys
    for url in sys.argv[1:]:
        row = load(url)
        print(row['status'], row['bytes'], len(row['text']), url)
