"""Copy reviewed delivery files into the dedicated Git checkout."""
from pathlib import Path
from zipfile import ZipFile
import shutil

root = Path(__file__).resolve().parents[1]
target = root / '.delivery' / 'recitation-plan'
if not (target / '.git').exists():
    raise SystemExit('Clone the target repository before syncing.')
with ZipFile(root / 'output' / '背诵计划-设计交付.zip') as archive:
    for item in archive.infolist():
        relative = Path(item.filename)
        destination = (target / relative).resolve()
        if not destination.is_relative_to(target.resolve()):
            raise ValueError('Archive path outside checkout')
        if item.is_dir():
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(item) as source, destination.open('wb') as output:
            shutil.copyfileobj(source, output)
print('Reviewed sources synchronized to dedicated checkout.')
