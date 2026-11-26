#!/bin/bash
# Checks the translations in assets/idiomas: every text the code shows (each tr("…") in Sources/kawaru) has to be
# in every language, with the same %@ and %lld in it. scripts/build.sh runs it, so a missing one stops the build.
#   scripts/idiomas.sh              check
#   scripts/idiomas.sh --plantilla  write es.lproj/Localizable.strings again from the code (the list to translate)
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-}" <<'PY'
import glob, os, plistlib, re, subprocess, sys
keys = []
for path in sorted(glob.glob('Sources/kawaru/*.swift')):
    for key in re.findall(r'\btr\("((?:[^"\\]|\\.)*)"', open(path, encoding='utf-8').read()):
        if key not in keys: keys.append(key)
quote = lambda s: '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
if sys.argv[1] == '--plantilla':
    with open('assets/idiomas/es.lproj/Localizable.strings', 'w', encoding='utf-8') as out:
        out.write('/* Spanish is the language the code is written in: each text stands for itself. Made by scripts/idiomas.sh --plantilla. */\n')
        for key in keys: out.write(f'{quote(key)} = {quote(key)};\n')
    print(f'{len(keys)} textos en es.lproj'); sys.exit(0)
marks = lambda s: sorted(re.findall(r'%(?:\d+\$)?(@|lld)', s))
bad = 0
for folder in sorted(glob.glob('assets/idiomas/*.lproj')):
    for name in ('Localizable.strings', 'InfoPlist.strings'):
        path = os.path.join(folder, name)
        if not os.path.exists(path): print(f'FALTA {path}'); bad += 1; continue
        try: table = plistlib.loads(subprocess.run(['plutil', '-convert', 'xml1', '-o', '-', path], capture_output=True, check=True).stdout)
        except subprocess.CalledProcessError as e: print(f'MAL ESCRITO {path}: {e.stderr.decode().strip()}'); bad += 1; continue
        if name == 'InfoPlist.strings':
            if 'NSCameraUsageDescription' not in table: print(f'FALTA NSCameraUsageDescription en {path}'); bad += 1
            continue
        for key in keys:
            if key not in table: print(f'FALTA en {folder}: {key}'); bad += 1
            elif marks(key) != marks(table[key]): print(f'VARIABLES DISTINTAS en {folder}: {key} -> {table[key]}'); bad += 1
        for key in table:
            if key not in keys: print(f'SOBRA en {folder}: {key}'); bad += 1
if bad: sys.exit(f'{bad} problema(s) en las traducciones')
print(f'OK  traducciones: {len(keys)} textos en {len(glob.glob("assets/idiomas/*.lproj"))} idiomas')
PY
