"""Wait until LOGFILE has a result with the given label. Usage: waitlog.py LOGFILE LABEL [timeout]"""
import json
import os
import sys
import time

logfile, label = sys.argv[1], sys.argv[2]
timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 120
start = time.time()
while time.time() - start < timeout:
    if os.path.exists(logfile):
        with open(logfile) as f:
            if any(json.loads(line).get('label') == label for line in f):
                print('ok', label)
                sys.exit(0)
    time.sleep(0.5)
print('TIMEOUT', label)
sys.exit(1)
