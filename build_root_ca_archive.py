"""Convert Google's PEM root bundle into an ESP8266 BearSSL CertStore archive.

Run from this directory: python build_root_ca_archive.py
The resulting data/certs.ar must be uploaded to the ESP8266 LittleFS image.
"""

import base64
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "root_ca_bundle"
OUTPUT = ROOT / "data" / "certs.ar"


def find_ar():
    found = shutil.which("xtensa-lx106-elf-ar")
    if found:
        return found
    local = Path(os.environ.get("LOCALAPPDATA", ""))
    matches = sorted(
        (local / "Arduino15" / "packages" / "esp8266" / "tools").glob(
            "xtensa-lx106-elf-gcc/*/bin/xtensa-lx106-elf-ar.exe"
        )
    )
    if not matches:
        raise SystemExit("ESP8266 ar tool not found; install the ESP8266 Arduino core.")
    return str(matches[-1])


def main():
    bundle = SOURCE.read_text(encoding="ascii")
    blocks = re.findall(
        r"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----",
        bundle,
        re.DOTALL,
    )
    if not blocks:
        raise SystemExit(f"No PEM certificates found in {SOURCE}")
    if bundle.count("-----END CERTIFICATE-----") != len(blocks):
        raise SystemExit("Certificate markers in the bundle do not match")

    OUTPUT.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        der_files = []
        for index, block in enumerate(blocks):
            der = base64.b64decode("".join(block.split()), validate=True)
            if not der or der[0] != 0x30:
                raise SystemExit(f"Invalid DER certificate at index {index}")
            path = Path(temp) / f"ca_{index:03d}.der"
            path.write_bytes(der)
            der_files.append(str(path))
        # Build fresh each time so an updated bundle cannot retain old roots.
        archive = Path(temp) / "certs.ar"
        subprocess.run([find_ar(), "q", str(archive), *der_files], check=True)
        shutil.copyfile(archive, OUTPUT)
    print(f"Prepared {len(blocks)} CA certificates in data/certs.ar")


if __name__ == "__main__":
    main()
