"""Bloco H (v3): sorteia os itens pelas regras de tarefas-v3.md e grava o gabarito pelo gh.
População: issues/PRs de swiftlang/swift-package-manager criadas nos últimos 120 dias, corpo ≤ 4000 caracteres,
ordenadas pelo número. rng = random.Random(semente), sorteios na ordem H1..H5 (G não sorteou nesta sessão).
Uso: python3 gabarito_h3.py <semente> <saida.json> [--so-gabarito <entrada.json>]  (o 2º modo recalcula o gabarito dos mesmos itens)"""
import datetime, json, random, subprocess, sys
REPO = "swiftlang/swift-package-manager"
def gh(*a): return json.loads(subprocess.check_output(['gh', *a]))
def busca(q):
    itens, pag = [], 1
    while True:
        r = gh('api', '-X', 'GET', 'search/issues', '-f', f'q=repo:{REPO} {q}', '-f', 'per_page=100', '-f', f'page={pag}')
        itens += r['items']
        if len(r['items']) < 100 or len(itens) >= 1000: return itens
        pag += 1
def item(n): return gh('api', f'repos/{REPO}/issues/{n}')
def draft_total(): return gh('api', '-X', 'GET', 'search/issues', '-f', f'q=repo:{REPO} is:pr is:open draft:true', '-f', 'per_page=1')['total_count']

def gabarito(nums):
    i1, i2, i3, pr, i5 = (item(n) for n in nums)
    p = gh('api', f'repos/{REPO}/pulls/{nums[3]}')
    tz = datetime.timezone(datetime.timedelta(hours=-3))
    fech = datetime.datetime.fromisoformat(i5['closed_at'].replace('Z', '+00:00')).astimezone(tz).date().isoformat() if i5['closed_at'] else None
    return {
        "H1": {"n": nums[0], "responsaveis": [a['login'] for a in i1['assignees']], "estado": i1['state']},
        "H2": {"n": nums[1], "responsaveis": sorted(a['login'] for a in i2['assignees'])},
        "H3": {"n": nums[2], "autor": i3['user']['login']},
        "H4": {"n": nums[3], "titulo": p['title'], "estado": p['state'], "merged": bool(p.get('merged')), "draft": bool(p.get('draft')),
               "corpo": p.get('body') or "", "autor": p['user']['login']},
        "H5": {"n": nums[4], "fechada_em_sp": fech, "closed_at": i5['closed_at'], "estado": i5['state']},
        "H6": {"total": draft_total()},
    }

if __name__ == '__main__':
    sem, saida = int(sys.argv[1]), sys.argv[2]
    if '--so-gabarito' in sys.argv:
        ent = json.load(open(sys.argv[sys.argv.index('--so-gabarito') + 1]))
        g = gabarito(ent['numeros']); json.dump({**ent, "calculado_em": datetime.datetime.now().isoformat(timespec='seconds'), "gabarito": g},
                                                open(saida, 'w'), ensure_ascii=False, indent=1); sys.exit()
    desde = (datetime.date.today() - datetime.timedelta(days=120)).isoformat()
    pop = [i for i in busca(f'created:>={desde}') if len(i.get('body') or '') <= 4000]
    pop.sort(key=lambda i: i['number'])
    iss = [i for i in pop if 'pull_request' not in i]
    prs = [i for i in pop if 'pull_request' in i]
    grupos = {
        "H1": [i for i in iss if i['state'] == 'open' and not i['assignees']],
        "H2": [i for i in iss if i['assignees']],
        "H3": iss,
        "H4": [i for i in prs if (i['pull_request'] or {}).get('merged_at')],
        "H5": [i for i in iss if i['state'] == 'closed'],
    }
    rng = random.Random(sem)
    nums = [rng.choice(grupos[k])['number'] for k in ("H1", "H2", "H3", "H4", "H5")]
    out = {"repo": REPO, "semente": sem, "populacao": {k: len(v) for k, v in grupos.items()}, "numeros": nums,
           "calculado_em": datetime.datetime.now().isoformat(timespec='seconds'), "gabarito": gabarito(nums)}
    json.dump(out, open(saida, 'w'), ensure_ascii=False, indent=1)
    print(out['populacao'], nums)
