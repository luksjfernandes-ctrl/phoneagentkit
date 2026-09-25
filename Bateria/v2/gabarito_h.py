"""Bloco H (v2): sorteia {n} (issue), {n_pr} (PR) e {rótulo}, e calcula o gabarito pela API do GitHub (gh), na hora da rodada.
Saída: h.json (copiado para o app). Uso: python3 gabarito_h.py <semente>"""
import datetime, json, random, subprocess, sys
REPO = "apple/swift-openapi-generator"
rnd = random.Random(int(sys.argv[1]))
def gh(*a): return json.loads(subprocess.check_output(['gh', *a]))
desde = (datetime.date.today() - datetime.timedelta(days=90)).isoformat()
itens = gh('api', '-X', 'GET', 'search/issues', '-f', f'q=repo:{REPO} created:>={desde}', '-f', 'per_page=100', '--jq', '.items')
issues = [i for i in itens if 'pull_request' not in i]
prs = [i for i in itens if 'pull_request' in i]
iss = rnd.choice(issues)
prn = rnd.choice(prs)['number']
pr = gh('api', f'repos/{REPO}/pulls/{prn}')
todos_rotulos = sorted({l['name'] for l in gh('api', f'repos/{REPO}/labels?per_page=100')})
# rótulo sorteado entre os que aparecem em issues abertas (lista via REST, sem varrer a busca rótulo a rótulo)
abertas = gh('issue', 'list', '-R', REPO, '--state', 'open', '--limit', '500', '--json', 'labels')
com_aberta = sorted({l['name'] for i in abertas for l in i['labels']})
rot = rnd.choice(com_aberta)
total = gh('api', '-X', 'GET', 'search/issues', '-f', f'q=repo:{REPO} is:issue is:open label:"{rot}"', '-f', 'per_page=1', '--jq', '.total_count')
n = iss['number']
g = {
    "repo": REPO, "semente": int(sys.argv[1]), "calculado_em": datetime.datetime.now().isoformat(timespec='seconds'),
    "rotulos_do_repo": todos_rotulos,
    "tarefas": [
        {"id": "H1", "chip": "resumir", "frase": f"resume a issue {n}", "n": n, "titulo": iss['title'], "estado": iss['state']},
        {"id": "H2", "chip": "responsavel", "frase": f"quem cuida da {n}?", "n": n, "responsaveis": [a['login'] for a in iss['assignees']]},
        {"id": "H3", "chip": "estado", "frase": f"a {n} ainda está aberta?", "n": n, "estado": iss['state']},
        {"id": "H4", "chip": "rotulos", "frase": f"quais rótulos a {n} tem?", "n": n, "rotulos": [l['name'] for l in iss['labels']]},
        {"id": "H5", "chip": "resumir_pr", "frase": f"summarize PR {prn}", "n": prn, "titulo": pr['title'], "estado": pr['state'],
         "merged": bool(pr.get('merged')), "draft": bool(pr.get('draft'))},
        {"id": "H6", "chip": "contar", "frase": f"quantas issues abertas com o rótulo {rot}?", "rotulo": rot, "total": total},
    ],
}
json.dump(g, open('h.json', 'w'), ensure_ascii=False, indent=1)
for t in g['tarefas']: print(t['id'], t['frase'], '→', {k: v for k, v in t.items() if k not in ('id', 'frase', 'chip')})
