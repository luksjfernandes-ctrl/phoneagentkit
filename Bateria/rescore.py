"""Corretor v2 (pós-rodada, só o corretor; o agente não mudou).
Correções registradas no relatório:
 1. normalização tira emoji e pontuação dos dois lados (o modelo remove emoji dos títulos);
 2. título conta como citado se as palavras (>=3 letras) dos 4 primeiros termos aparecem na resposta, em qualquer ordem
    ("Equipe — Reunião Geral" = "reunião geral da equipe");
 3. código entre colchetes no início do título ("[ABC-123] ...") não conta: o modelo o omite e cita o evento certo.
Uso: python3 rescore.py brutos/<aparelho>/b4-*.json"""
import json, re, sys, unicodedata
from collections import defaultdict

def norm(s):
    s = unicodedata.normalize('NFKD', s.lower())
    s = ''.join(c for c in s if not unicodedata.combining(c))
    return ' '.join(re.sub(r'[^a-z0-9]+', ' ', s).split())

def citado(titulo, resp):
    titulo = re.sub(r'^\s*\[[^\]]*\]\s*', '', titulo)
    palavras = [w for w in norm(titulo).split()[:4] if len(w) >= 3] or norm(titulo).split()[:1]
    r = ' ' + resp + ' '
    return all(f' {w} ' in r for w in palavras)

NEG = ['nao ', 'nenhum', 'nada', 'none', 'nothing', 'no event', 'no reminder', 'no photo', 'don t', 'do not', 'there are no', 'you have no']

def corrigir(r, g):
    n = norm(r['resposta'])
    if 'titulos' in g:
        ts = g['titulos']['_0']
        if not ts: return 'ok' if any(x in n + ' ' for x in NEG) else 'falhou: esperava nada'
        faltam = [t for t in ts if not citado(t, n)]
        return 'ok' if not faltam else f'falhou: faltam {len(faltam)}/{len(ts)}'
    return r['nota']  # numero/telefone/foto/diaSemana: corretor v1 mantido (nota gravada no app)

for f in sys.argv[1:]:
    d = json.load(open(f))
    print(f, d['aparelho'], 'commit', d['commit'])
    placar = defaultdict(lambda: defaultdict(list))
    for r in d['resultados']:
        r['nota2'] = corrigir(r, r['gabarito'])
        placar[r['modo']][r['tarefa']].append(r['nota2'] == 'ok')
    for modo, ts in placar.items():
        passou = {t: sum(v) >= 2 for t, v in ts.items()}
        print(f"  {modo}: {sum(passou.values())}/{len(passou)} tarefas (>=2/3) · {sum(sum(v) for v in ts.values())}/{sum(len(v) for v in ts.values())} respostas")
        for t, v in ts.items(): print(f"    {t} {''.join('✓' if x else '✗' for x in v)}")
    json.dump(d, open(f.replace('.json', '.v2.json'), 'w'), ensure_ascii=False, indent=1)
