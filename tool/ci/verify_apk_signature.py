"""Fail unless every APK given is signed with Absorb Plus's permanent key.

The expected certificate SHA-256 is public (tool/android-signing-cert-sha256.txt);
the key itself lives only in GitHub secrets and the owner's backup.
Usage: python3 tool/ci/verify_apk_signature.py APK...   (needs Android build-tools)
"""

import glob
import os
import re
import subprocess
import sys
from pathlib import Path

EXPECTED_FILE = Path(__file__).resolve().parents[1] / "android-signing-cert-sha256.txt"


def apksigner() -> str:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or ""
    name = "apksigner.bat" if os.name == "nt" else "apksigner"
    tools = sorted(glob.glob(os.path.join(sdk, "build-tools", "*", name)))
    if not tools:
        sys.exit("apksigner not found (ANDROID_HOME/build-tools/*/apksigner)")
    return tools[-1]


def main(apks: list[str]) -> int:
    expected = re.sub(r"[^0-9a-f]", "", EXPECTED_FILE.read_text().lower())
    if not apks:
        sys.exit("no APKs given")
    tool = apksigner()
    bad = 0
    for apk in apks:
        out = subprocess.run([tool, "verify", "--print-certs", apk], capture_output=True,
                             text=True)
        digests = re.findall(r"certificate SHA-256 digest:\s*([0-9a-fA-F:]+)", out.stdout)
        actual = {re.sub(r"[^0-9a-f]", "", d.lower()) for d in digests}
        if out.returncode != 0 or actual != {expected}:
            bad += 1
            print(f"WRONG SIGNATURE: {apk}\n{out.stdout}{out.stderr}")
        else:
            print(f"ok: {Path(apk).name} is signed with the Absorb Plus key")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
