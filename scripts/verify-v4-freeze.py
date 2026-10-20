#!/usr/bin/env python3
"""Confere o congelamento v4 sem ler tarefas cegas ou chamar o agente."""
import argparse
import hashlib
from pathlib import Path
import re
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
args = parser.parse_args()
root = args.root.resolve()
manifest = root / 'Bateria/v4/CONGELAMENTO.md'
try:
    entries = re.findall(r'^([a-f0-9]{64})  (.+)$', manifest.read_text(), re.MULTILINE)
except OSError:
    sys.exit('Manifesto v4 não encontrado.')
if not entries:
    sys.exit('Manifesto sem hashes; verificação recusada.')
errors = []
for expected, relative in entries:
    target = (root / relative).resolve()
    if not target.is_relative_to(root):
        errors.append(f'Caminho fora do repositório: {relative}')
        continue
    try:
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
    except OSError:
        errors.append(f'Arquivo ausente: {relative}')
        continue
    if actual != expected:
        errors.append(f'Hash divergente: {relative}')
if errors:
    sys.exit('\n'.join(errors))
print(f'{len(entries)} arquivos conferem com o congelamento v4. A bateria não foi executada.')
