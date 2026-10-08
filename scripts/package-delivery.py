"""Package reviewed sources and artifacts without SDKs, caches or databases."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
destination = root / 'output' / '背诵计划-设计交付.zip'
with ZipFile(destination, 'w', ZIP_DEFLATED) as package:
    for folder in ['.github', 'docs', 'ui', 'scripts', 'product']:
        for file in (root / folder).rglob('*'):
            if not file.is_file():
                continue
            relative = file.relative_to(root)
            if any(part in {'.dart_tool', 'build', '__pycache__', '.idea', '.gradle', '.symlinks', 'ephemeral'} for part in relative.parts):
                continue
            if file.suffix == '.iml' or file.name in {'local.properties', 'Generated.xcconfig', 'flutter_export_environment.sh', '.flutter-plugins-dependencies'}:
                continue
            package.write(file, relative)
    for name in ['README.md', 'AGENTS.md', '.gitignore']:
        package.write(root / name, name)
    for file in (root / 'output' / 'ui').iterdir():
        if file.suffix in {'.png', '.json'}:
            package.write(file, file.relative_to(root))
    result = root / 'output' / 'local-verification' / 'verification.json'
    if result.exists():
        package.write(result, result.relative_to(root))
    for file in (root / 'output' / 'native-ui').glob('*.png'):
        package.write(file, file.relative_to(root))
print(f'Packaged {len(ZipFile(destination).namelist())} files; SDK and caches excluded.')
