#!/usr/bin/env python3
"""Run one owned desktop build; retain only a non-sensitive startup summary."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', required=True, type=Path)
    parser.add_argument('--expected-revision', required=True)
    parser.add_argument('--summary', required=True, type=Path)
    parser.add_argument('--timeout', type=float, default=30)
    args = parser.parse_args()
    if not args.executable.is_absolute() or not args.executable.is_file():
        parser.error('--executable must name an existing absolute file')
    if not 0 < args.timeout <= 30:
        parser.error('--timeout must be greater than zero and at most 30 seconds')
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.expected_revision):
        parser.error('--expected-revision must be a source revision identifier')

    result = {
        'scope': 'desktop_startup_only_no_login_verification',
        'platform': sys.platform,
        'expectedRevision': args.expected_revision,
        'revisionMatches': False,
        'readyObserved': False,
        'splashExitObserved': False,
        'status': 'FAIL',
        'reason': 'startup_timeout',
        'processExitCode': None,
    }
    process = None
    started = time.monotonic()
    # The private temporary directory and raw output are never uploaded. Only
    # allowlisted booleans/exit codes enter the artifact, not URLs or logs.
    with tempfile.TemporaryDirectory(prefix='daviewer-startup-') as temporary:
        raw_path = Path(temporary) / 'stdout.private'
        try:
            options = {}
            if os.name == 'nt':
                startup = subprocess.STARTUPINFO()
                startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                startup.wShowWindow = subprocess.SW_HIDE
                options.update(startupinfo=startup,
                               creationflags=subprocess.CREATE_NO_WINDOW)
            with raw_path.open('wb') as output:
                process = subprocess.Popen(
                    [str(args.executable)], cwd=args.executable.parent,
                    stdin=subprocess.DEVNULL, stdout=output,
                    stderr=subprocess.STDOUT, **options)
                offset = 0
                buffered = ''
                while time.monotonic() - started < args.timeout:
                    with raw_path.open('rb') as source:
                        source.seek(offset)
                        data = source.read(1 << 20)
                        offset += len(data)
                    buffered += data.decode('utf-8', errors='replace')
                    lines = buffered.split('\n')
                    buffered = lines.pop()[-65536:]
                    for line in lines:
                        revision = re.search(r'\bbuildRevision=([A-Za-z0-9_-]+)', line)
                        if revision:
                            result['revisionMatches'] |= revision[1] == args.expected_revision
                        if re.search(r'\bready=true\b', line):
                            result['readyObserved'] = True
                            target = re.search(r'\broute=/splash\s+target=(/[^\s]*)', line)
                            if target and target[1] != '/splash':
                                result['splashExitObserved'] = True
                    exit_code = process.poll()
                    if exit_code is not None:
                        result.update(reason='process_exited_before_startup', processExitCode=exit_code)
                        break
                    if all(result[key] for key in (
                            'revisionMatches', 'readyObserved', 'splashExitObserved')):
                        result.update(status='PASS', reason='startup_ready')
                        break
                    time.sleep(0.1)
        except (OSError, ValueError) as error:
            result['reason'] = 'launch_or_capture_failed'
            result['errorType'] = type(error).__name__
        finally:
            # Never enumerate, kill by name, or terminate another app instance.
            if process is not None and process.poll() is None:
                try:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
                except (OSError, subprocess.TimeoutExpired) as error:
                    result.update(status='FAIL', reason='owned_process_cleanup_failed',
                                  errorType=type(error).__name__)
    result['elapsedSeconds'] = round(time.monotonic() - started, 3)
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, separators=(',', ':')))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
