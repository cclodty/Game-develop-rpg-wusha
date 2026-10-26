"""Package all catalogue data, original atlas PNGs, and maintenance scripts."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'wuxia-items-368.zip'


def main():
    files = sorted(p for p in ROOT.rglob('*') if p.is_file()
                   and p.suffix not in {'.zip', '.pyc'}
                   and '__pycache__' not in p.parts
                   and p.name not in {'SHA256SUMS.txt', 'wuxia-items-368.zip.tmp'})
    sums = '\n'.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.relative_to(ROOT).as_posix()
                     for p in files) + '\n'
    checksums = ROOT / 'SHA256SUMS.txt'
    checksums.write_text(sums, encoding='utf-8')
    files.append(checksums)
    temp = ROOT / 'wuxia-items-368.zip.tmp'
    with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p, arcname='wuxia-item-library/' + p.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(temp) as z:
        assert z.testzip() is None
        assert len(z.namelist()) == len(files)
    temp.replace(OUT)
    print(f'{OUT}: {OUT.stat().st_size:,} bytes, {len(files)} files')


if __name__ == '__main__':
    main()
