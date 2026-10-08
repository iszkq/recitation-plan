"""Fetch the engine-matched Dart SDK via Python TLS on restricted Windows hosts."""
import os
from pathlib import Path
import urllib.request
import zipfile

os.environ.pop('SSLKEYLOGFILE', None)
root = Path(__file__).resolve().parents[1] / '.tools' / 'flutter'
cache = root / 'bin' / 'cache'
engine = (cache / 'engine.stamp').read_text().strip()
url = f'https://storage.googleapis.com/flutter_infra_release/flutter/{engine}/dart-sdk-windows-x64.zip'
archive = cache / 'official-engine-dart.zip'
with urllib.request.urlopen(url, timeout=60) as response, archive.open('wb') as output:
    while chunk := response.read(1024 * 1024):
        output.write(chunk)
with zipfile.ZipFile(archive) as package:
    package.extractall(cache)
(cache / 'engine-dart-sdk.stamp').write_text(engine, encoding='ascii')
print('Engine-matched official Dart SDK ready', flush=True)
