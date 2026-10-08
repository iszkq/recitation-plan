"""Install a pinned official Dart SDK in the workspace without changing PATH."""
import hashlib
import os
from pathlib import Path
import urllib.request
import zipfile

os.environ.pop('SSLKEYLOGFILE', None)
root = Path(__file__).resolve().parents[1]
destination = root / '.tools'
destination.mkdir(exist_ok=True)
version = '3.13.5'
base = f'https://storage.googleapis.com/dart-archive/channels/stable/release/{version}/sdk/dartsdk-windows-x64-release.zip'
archive = destination / f'dart-{version}.zip'
with urllib.request.urlopen(base + '.sha256sum', timeout=30) as response:
    expected = response.read().decode().split()[0]
if not archive.exists():
    with urllib.request.urlopen(base, timeout=60) as response, archive.open('wb') as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
actual = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest()
if actual != expected:
    raise RuntimeError('Dart SDK checksum mismatch')
with zipfile.ZipFile(archive) as package:
    package.extractall(destination)
print(f'Dart {version}: checksum verified and installed in .tools/dart-sdk', flush=True)
