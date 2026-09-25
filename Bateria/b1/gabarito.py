"""B1 via Composio (GitHub): sorteia {item}/{rótulo} e calcula o gabarito pela API do GitHub (gh), na hora da rodada.
Saída: b1.json (tarefas + gabarito), copiado para o app. Uso: python3 gabarito.py <owner/repo> <semente>"""
import json, random, subprocess, sys
from collections import Counter
repo, semente = sys.argv[1], int(sys.argv[2])
rnd = random.Random(semente)
def gh(*a): return json.loads(subprocess.check_output(['gh', *a]))
abertas = gh('issue', 'list', '-R', repo, '--state', 'open', '--limit', '1000',
             '--json', 'number,title,createdAt,labels,assignees,milestone')
mais_antiga = min(abertas, key=lambda i: i['createdAt'])
com_resp = [i for i in abertas if i['assignees']]
item3 = rnd.choice(abertas)
item5 = rnd.choice(com_resp)
cont = Counter(l['name'] for i in abertas for l in i['labels'])
rotulo = rnd.choice(sorted(n for n, c in cont.items() if 2 <= c <= 8))
com_rotulo = sorted(i['number'] for i in abertas if any(l['name'] == rotulo for l in i['labels']))
ms = gh('api', f'repos/{repo}/milestones?state=open')
atrasadas = []  # prazo do milestone < hoje e issue aberta
import datetime
hoje = datetime.datetime.now(datetime.timezone.utc).isoformat()
for m in ms:
    if m.get('due_on') and m['due_on'] < hoje:
        atrasadas += [i['number'] for i in abertas if i['milestone'] and i['milestone']['title'] == m['title']]
p = f'@{repo}'
tarefas = [
    {"id": "B1.1", "pedido": f"Quantas issues abertas tem em {p}?", "gabarito": {"numero": len(abertas)}},
    {"id": "B1.2", "pedido": f"Qual é a issue aberta mais antiga de {p}?", "gabarito": {"issue": mais_antiga['number'], "titulo": mais_antiga['title']}},
    {"id": "B1.3", "pedido": f"Resume em 2 frases a issue @#{item3['number']} de {p}", "gabarito": {"issue": item3['number'], "titulo": item3['title'], "estado": "open"}},
    {"id": "B1.4", "pedido": f"Tem alguma coisa atrasada em {p}?", "gabarito": {"lista": sorted(atrasadas)},
     "nota": "não aplicável: nenhum milestone aberto tem prazo" if not any(m.get('due_on') for m in ms) else ""},
    {"id": "B1.5", "pedido": f"Quem é o responsável pela issue @#{item5['number']} de {p}?", "gabarito": {"logins": [a['login'] for a in item5['assignees']]}},
    {"id": "B1.6", "pedido": f"Lista as issues de {p} com o rótulo {rotulo}", "gabarito": {"lista": com_rotulo}},
]
json.dump({"repo": repo, "semente": semente, "calculado_em": hoje, "tarefas": tarefas}, open('b1.json', 'w'), ensure_ascii=False, indent=1)
for t in tarefas: print(t['id'], t['pedido'], '→', t['gabarito'])
