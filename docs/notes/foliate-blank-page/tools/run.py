"""Run one driver scenario in a headless browser and wait for its result in the log.

Usage: python3 -I run.py chrome|firefox LOGFILE PROFILE_DIR 'query=string&label=x' [timeout]
"""
import json
import os
import shutil
import subprocess
import sys
import time

engine, logfile, profiles, query = sys.argv[1:5]
timeout = float(sys.argv[5]) if len(sys.argv) > 5 else 120
params = dict(p.split('=', 1) for p in query.split('&'))
label = params['label']
w, h = int(params.get('w', 390)), int(params.get('h', 844))
url = f'http://127.0.0.1:8765/driver/driver.html?{query}'

profile = os.path.join(profiles, f'{engine}-{label}')
shutil.rmtree(profile, ignore_errors=True)
os.makedirs(profile)

if engine == 'chrome':
    cmd = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '--headless=new',
           f'--user-data-dir={profile}', '--no-first-run', '--no-default-browser-check',
           '--disable-extensions', f'--window-size={w + 40},{h + 80}', url]
elif engine == 'firefox':
    cmd = ['/Applications/Firefox.app/Contents/MacOS/firefox', '--headless', '--no-remote',
           '--profile', profile, f'--window-size={w + 40},{h + 80}', url]
else:
    sys.exit(f'unknown engine {engine}')


def find():
    if not os.path.exists(logfile):
        return None
    with open(logfile) as f:
        for line in f:
            d = json.loads(line)
            if d.get('label') == label:
                return d
    return None


proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
start = time.time()
result = None
while time.time() - start < timeout:
    result = find()
    if result:
        break
    time.sleep(0.5)
proc.terminate()
try:
    proc.wait(10)
except subprocess.TimeoutExpired:
    proc.kill()
shutil.rmtree(profile, ignore_errors=True)
print('ok' if result else 'TIMEOUT', label)
