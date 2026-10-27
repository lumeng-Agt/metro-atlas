"""Run the gameplay checks a release has to pass and record the result.

This is the release gate now: the independent evidence audit is reported in the
update notes, but what decides whether a build may ship is whether the game
actually plays — every city from a new game to the last published chapter, a
save picked up again in a separate process, and the suites that cover saving,
layout, editing and chapter lookup.

The record carries the source fingerprint it was produced against, and
`build_packages.py` recomputes that fingerprint before trusting it, so a stale
or hand-written record cannot ship a build.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gameplay_spec
from build_packages import current_version, source_manifest_hash

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
GODOT_PROFILE = ROOT / '.tools/profile'
DATA_ROOT = Path('D:/gam1/testdata/gameplay-verify')
MAX_WORKERS = 5

FAILURES = re.compile(r'REPLAY_FAILURES\s+(\d+)\s+checkpoints=(\d+)')
DONE = re.compile(r'REPLAY_CITY_DONE\s+(\S+)\s+visited=(\d+)\s+phase=(\S+)')
FREE_OK = re.compile(r'REPLAY_FREE_UNLOCK_OK\s+(\S+)')
# The CI already treats these as fatal; a script that prints them and still
# exits 0 has not passed.
SCRIPT_ERROR = re.compile(r'SCRIPT ERROR:|Failed to load script')


def _script_errors(output):
    return len(SCRIPT_ERROR.findall(output or ''))


def _godot_env():
    env = dict(os.environ)
    # Godot looks for export templates under %APPDATA%; this project keeps them
    # inside the repository so the toolchain stays self-contained.
    env['APPDATA'] = str(GODOT_PROFILE)
    return env


def _run_godot(script, data_dir, extra_env=None, timeout=3600):
    env = _godot_env()
    env.update(extra_env or {})
    data_dir.mkdir(parents=True, exist_ok=True)
    command = [str(GODOT), '--headless', '--path', str(ROOT), '--script', f'res://{script}',
               '--', f'--data-dir={data_dir.as_posix()}']
    started = time.time()
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True,
                            timeout=timeout, errors='replace')
    return result, time.time() - started


def _replay_check(city, data_dir, extra_env):
    result, elapsed = _run_godot('tests/campaign_replay_all_cities.gd', data_dir,
                                 {'METRO_REPLAY_CITY': city, 'METRO_REPLAY_FUTURE': '1', **extra_env})
    output = result.stdout + result.stderr
    failures = FAILURES.search(output)
    done = DONE.search(output)
    return {
        'exitCode': result.returncode,
        'failures': int(failures.group(1)) if failures else None,
        'checkpoints': int(failures.group(2)) if failures else 0,
        'visited': int(done.group(2)) if done else 0,
        'endPhase': done.group(3) if done else '',
        'freeUnlock': bool(FREE_OK.search(output)),
        'scriptErrors': _script_errors(output),
        'durationSeconds': round(elapsed, 1),
        'evidence': (failures.group(0) if failures else '') + (' | ' + done.group(0) if done else ''),
    }


def check_fresh(city):
    data_dir = DATA_ROOT / f'{city}-fresh'
    shutil.rmtree(data_dir, ignore_errors=True)
    row = _replay_check(city, data_dir, {'METRO_REPLAY_FREE_UNLOCK': '1'})
    floor = gameplay_spec.CHECKPOINT_FLOOR[city]
    row['checkpointFloor'] = floor
    row['ok'] = (row['exitCode'] == 0 and row['failures'] == 0 and row['scriptErrors'] == 0
                 and row['checkpoints'] >= floor and row['freeUnlock'])
    if not row['freeUnlock']:
        row['note'] = 'replay finished without reaching free creation'
    return {'id': f'replay.fresh.{city}', 'kind': 'replay', 'city': city, 'mode': 'fresh', **row}


def check_resume(city):
    """Run half the city, then pick the save up in a second process."""
    data_dir = DATA_ROOT / f'{city}-resume'
    shutil.rmtree(data_dir, ignore_errors=True)
    part = _replay_check(city, data_dir, {'METRO_REPLAY_STOP_AFTER_INDEX': str(gameplay_spec.RESUME_BREAKPOINT)})
    resumed = _replay_check(city, data_dir, {'METRO_REPLAY_RESUME': '1'}) if part['exitCode'] == 0 else {
        'exitCode': 1, 'failures': None, 'checkpoints': 0, 'visited': 0, 'endPhase': '',
        'freeUnlock': False, 'scriptErrors': 1, 'durationSeconds': 0.0, 'evidence': 'part run failed'}
    ok = (part['exitCode'] == 0 and part['failures'] == 0 and part['scriptErrors'] == 0
          and resumed['exitCode'] == 0 and resumed['failures'] == 0 and resumed['scriptErrors'] == 0
          and resumed['checkpoints'] > 0)
    return {'id': f'replay.resume.{city}', 'kind': 'replay', 'city': city, 'mode': 'resume',
            'breakpoint': gameplay_spec.RESUME_BREAKPOINT, 'ok': ok,
            'part': {k: part[k] for k in ('exitCode', 'failures', 'checkpoints', 'visited', 'scriptErrors')},
            'resume': {k: resumed[k] for k in ('exitCode', 'failures', 'checkpoints', 'visited',
                                               'endPhase', 'scriptErrors')},
            'durationSeconds': round(part['durationSeconds'] + resumed['durationSeconds'], 1),
            'evidence': f"part {part['evidence']} || resume {resumed['evidence']}"}


def check_gd(name, script):
    data_dir = DATA_ROOT / f'{name.replace(".", "-")}'
    shutil.rmtree(data_dir, ignore_errors=True)
    result, elapsed = _run_godot(script, data_dir, timeout=1800)
    output = result.stdout + result.stderr
    errors = _script_errors(output)
    tail = [line for line in output.splitlines() if line.strip()][-3:]
    return {'id': name, 'kind': 'gd', 'script': script,
            'ok': result.returncode == 0 and errors == 0,
            'exitCode': result.returncode, 'scriptErrors': errors,
            'durationSeconds': round(elapsed, 1), 'evidence': ' | '.join(tail)[-400:]}


def check_py(name, command):
    started = time.time()
    result = subprocess.run([sys.executable, *command], cwd=ROOT, capture_output=True, text=True,
                            errors='replace', timeout=1800)
    tail = [line for line in (result.stdout + result.stderr).splitlines() if line.strip()][-3:]
    return {'id': name, 'kind': 'py', 'command': ' '.join(command), 'ok': result.returncode == 0,
            'exitCode': result.returncode, 'durationSeconds': round(time.time() - started, 1),
            'evidence': ' | '.join(tail)[-400:]}


def _rerun_serially(check, builder):
    """A parallel run can lose a save race; retry alone before calling it red."""
    if check['ok']:
        return check
    retry = builder()
    retry['retriedSerially'] = True
    return retry


def main():
    parser = argparse.ArgumentParser(description='Run the gameplay checks a release has to pass.')
    parser.add_argument('--version', default=current_version())
    parser.add_argument('--out', default='')
    args = parser.parse_args()

    if not GODOT.is_file():
        raise SystemExit(f'Godot binary missing: {GODOT}')
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    print(f'verifying {args.version}; fingerprint before run: {source_manifest_hash()[:16]}…')

    checks = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = [(city, pool.submit(check_fresh, city)) for city in gameplay_spec.REPLAY_CITIES]
        for city, future in futures:
            row = _rerun_serially(future.result(), lambda c=city: check_fresh(c))
            checks.append(row)
            print(f"  {row['id']:34s} ok={row['ok']} checkpoints={row.get('checkpoints')} free={row.get('freeUnlock')}")
        futures = [(city, pool.submit(check_resume, city)) for city in gameplay_spec.REPLAY_CITIES]
        for city, future in futures:
            row = _rerun_serially(future.result(), lambda c=city: check_resume(c))
            checks.append(row)
            print(f"  {row['id']:34s} ok={row['ok']} resume={row['resume'].get('checkpoints')}")

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        gd_futures = [(name, script, pool.submit(check_gd, name, script))
                      for name, script in gameplay_spec.GD_SCRIPTS]
        for name, script, future in gd_futures:
            row = _rerun_serially(future.result(), lambda n=name, s=script: check_gd(n, s))
            checks.append(row)
            print(f"  {row['id']:34s} ok={row['ok']}")

    for name, command in gameplay_spec.PY_CHECKS:
        row = check_py(name, command)
        checks.append(row)
        print(f"  {row['id']:34s} ok={row['ok']}")

    required = gameplay_spec.required_ids()
    present = {check['id'] for check in checks}
    missing = [name for name in required if name not in present]
    passed = sum(1 for check in checks if check['ok'])
    record = {
        'schema': 'gameplay-verification/1',
        'version': args.version,
        'generatedAt': datetime.now().astimezone().isoformat(timespec='seconds'),
        'manifestHash': source_manifest_hash(),
        'godot': '4.7.2-stable.win64.console',
        'requiredChecks': required,
        'missingChecks': missing,
        'checks': checks,
        'summary': {'total': len(checks), 'passed': passed, 'failed': len(checks) - passed,
                    'requiredTotal': len(required)},
    }
    out = Path(args.out) if args.out else ROOT / 'docs' / f'gameplay-verification-{args.version}.json'
    out.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"RECORD {out}")
    print(f"GAMEPLAY {passed}/{len(checks)} passed; missing {len(missing)}; failed {len(checks) - passed}")
    return 0 if passed == len(checks) and not missing else 1


if __name__ == '__main__':
    sys.exit(main())
