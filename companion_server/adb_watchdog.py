import subprocess
import time

while True:
    try:
        subprocess.run(["adb", "-s", "R3CRC0LYLWP", "reverse", "tcp:8000", "tcp:8000"], capture_output=True)
    except Exception:
        pass
    time.sleep(3)
