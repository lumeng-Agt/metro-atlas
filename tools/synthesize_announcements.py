"""Generate distributable offline cues with the MIT MeloTTS voice (no voice cloning).

Run with .tools/tts-env/Scripts/python.exe. The model stays in .tools; only
small Vorbis clips, their text ledger and the upstream license ship.
"""
from __future__ import annotations
import concurrent.futures
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import time
import wave

ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / ".tools/vits-melo-tts-zh_en"
OUTPUT = ROOT / "assets/announcements"
# Written homophones only guide synthesis. The UI always retains the real name.
OVERRIDES = {"莘庄": "新庄", "颛桥": "专桥", "西塱": "西朗", "石碁": "石旗",
             "大柏树": "大百树", "番禺": "潘鱼", "什刹海": "石岔海",
             "大葆台": "大宝台", "车陂": "车杯", "朝阳门": "潮阳门",
             "清㘵": "清布", "𧒽岗": "雷岗"}
_tts = None


def init_worker():
    import sherpa_onnx
    global _tts
    _tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            vits=sherpa_onnx.OfflineTtsVitsModelConfig(
                model=str(MODEL / "model.onnx"), tokens=str(MODEL / "tokens.txt"),
                lexicon=str(MODEL / "lexicon.txt"), dict_dir=str(MODEL / "dict")),
            num_threads=2, provider="cpu"),
        rule_fsts=",".join(str(MODEL / name) for name in ("date.fst", "number.fst", "phone.fst"))))


def spoken_for(name):
    spoken = name
    for original, phonetic in OVERRIDES.items(): spoken = spoken.replace(original, phonetic)
    spoken = re.sub(r"[（(][^）)]*号线[）)]", "", spoken)
    return spoken.replace("·", "，").replace("・", "，").replace("（", "，").replace("）", "")


def generate(name):
    import numpy as np
    spoken = spoken_for(name)
    text = f"下一站，{spoken}。"
    ident = hashlib.sha256(("melo-2024:" + text).encode()).hexdigest()[:24]
    target = OUTPUT / (ident + ".ogg")
    if not target.is_file():
        audio = _tts.generate(text, sid=0, speed=1.0)
        if not 0.35 <= len(audio.samples)/audio.sample_rate <= 15:
            raise RuntimeError(f"Invalid generated duration: {name}")
        temp = ROOT / ".tools" / f"announcement-{os.getpid()}.wav"
        with wave.open(str(temp), "wb") as stream:
            stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(audio.sample_rate)
            stream.writeframes((np.clip(audio.samples, -1, 1)*32767).astype(np.int16).tobytes())
        encoded = target.with_suffix(f".{os.getpid()}.tmp.ogg")
        subprocess.run([shutil.which("ffmpeg"), "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(temp), "-ar", "22050", "-c:a", "libvorbis", "-q:a", "3", str(encoded)], check=True)
        os.replace(encoded, target)
        temp.unlink()
    return {"id": ident, "name": name, "spokenText": text,
            "path": target.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "pronunciationReview": "dictionary_checked", "phoneticOverride": spoken != name}


def collect_names():
    cities = json.loads((ROOT / "data/cities.json").read_text(encoding="utf-8"))
    names = {station["name"] for city in cities["cities"] for station in city["stations"]}
    def visit(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "stationNames" and isinstance(item, dict): names.update(str(x) for x in item.values())
                else: visit(item)
        elif isinstance(value, list):
            for item in value: visit(item)
    visit(json.loads((ROOT / "data/campaigns.json").read_text(encoding="utf-8")))
    return sorted(name for name in names if name and len(name) <= 40)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    names = collect_names(); started = time.monotonic(); clips = []
    # Names/line qualifiers can share speech. Generate each utterance once so
    # parallel workers never overwrite a shared target after its hash was read.
    unique = {}
    for name in names: unique.setdefault(spoken_for(name), name)
    audio_by_text = {}
    with concurrent.futures.ProcessPoolExecutor(max_workers=4, initializer=init_worker) as pool:
        for index, clip in enumerate(pool.map(generate, unique.values())):
            audio_by_text[spoken_for(clip["name"])] = clip
            if index % 50 == 0: print(f"{index+1}/{len(names)} cues, {time.monotonic()-started:.1f}s", flush=True)
    for name in names:
        clip = dict(audio_by_text[spoken_for(name)])
        clip["name"] = name
        clips.append(clip)
    shutil.copyfile(MODEL / "LICENSE", OUTPUT / "LICENSE-MeloTTS.txt")
    manifest = {"schemaVersion": 1, "version": "2026.10.31.1", "license": "MIT",
                "modelSource": "https://huggingface.co/myshell-ai/MeloTTS-Chinese",
                "conversionSource": "https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models",
                "modelSha256": hashlib.sha256((MODEL / "model.onnx").read_bytes()).hexdigest(),
                "voiceNotice": "普通话示意合成声音，不模仿运营方播音员。",
                "reviewMethod": "词典前端与明确同音字覆盖；未取得真人全量听审，不宣称官方报站。",
                "phoneticOverrides": OVERRIDES, "clips": clips}
    (ROOT / "data/announcement_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"Finished {len(clips)} cues in {time.monotonic()-started:.1f}s", flush=True)
