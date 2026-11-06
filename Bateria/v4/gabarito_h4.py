"""Bloco H (v4): sorteia os itens pelas regras de tarefas-v4.md e grava o gabarito pelo gh.
População: issues/PRs de pola-rs/polars criadas nos últimos 120 dias, corpo ≤ 4000 caracteres, ordenadas pelo número.
A busca do GitHub corta em 1000 resultados: cada grupo é buscado por intervalos de 15 dias e unido pelo número.
rng = random.Random(semente), sorteios na ordem H1..H5 (H6 não sorteia).
Uso: python3 gabarito_h4.py <semente> <saida.json> [--so-gabarito <entrada.json>]  (o 2º modo recalcula o gabarito dos mesmos itens)"""
import datetime, json, random, subprocess, sys, time
REPO = "pola-rs/polars"
TZ = datetime.timezone(datetime.timedelta(hours=-3))   # America/Sao_Paulo (sem horário de verão desde 2019)

def gh(*a):
    for tentativa in range(5):
        try: return json.loads(subprocess.check_output(['gh', *a], stderr=subprocess.DEVNULL))
        except subprocess.CalledProcessError:
            time.sleep(20 * (tentativa + 1))   # limite secundário da busca
    raise SystemExit(f'gh falhou: {a}')

def busca(q, desde):
    """Une buscas por janelas de 15 dias (cada uma < 1000 itens)."""
    itens, ini, fim = {}, desde, datetime.date.today()
    while ini <= fim:
        sup = min(ini + datetime.timedelta(days=14), fim)
        pag = 1
        while True:
            r = gh('api', '-X', 'GET', 'search/issues', '-f', f'q=repo:{REPO} {q} created:{ini.isoformat()}..{sup.isoformat()}',
                   '-f', 'per_page=100', '-f', f'page={pag}')
            for i in r['items']: itens[i['number']] = i
            if len(r['items']) < 100 or pag >= 10: break
            pag += 1
            time.sleep(2)
        ini = sup + datetime.timedelta(days=1)
        time.sleep(2)
    return list(itens.values())

def item(n): return gh('api', f'repos/{REPO}/issues/{n}')
def draft_total(): return gh('api', '-X', 'GET', 'search/issues', '-f', f'q=repo:{REPO} is:pr is:open draft:true', '-f', 'per_page=1')['total_count']
def dia_sp(iso): return datetime.datetime.fromisoformat(iso.replace('Z', '+00:00')).astimezone(TZ).date().isoformat() if iso else None

def gabarito(nums):
    i1, i2, i3, pr, i5 = (item(n) for n in nums)
    p = gh('api', f'repos/{REPO}/pulls/{nums[3]}')
    return {
        "H1": {"n": nums[0], "responsaveis": [a['login'] for a in i1['assignees']], "estado": i1['state'], "titulo": i1['title']},
        "H2": {"n": nums[1], "responsaveis": sorted(a['login'] for a in i2['assignees']), "estado": i2['state'], "titulo": i2['title']},
        "H3": {"n": nums[2], "autor": i3['user']['login'], "titulo": i3['title'], "corpo": i3.get('body') or ""},
        "H4": {"n": nums[3], "titulo": p['title'], "estado": p['state'], "merged": bool(p.get('merged')), "draft": bool(p.get('draft')),
               "corpo": p.get('body') or "", "autor": p['user']['login']},
        "H5": {"n": nums[4], "fechada_em_sp": dia_sp(i5['closed_at']), "closed_at": i5['closed_at'], "estado": i5['state'], "titulo": i5['title']},
        "H6": {"total": draft_total()},
    }

if __name__ == '__main__':
    sem, saida = int(sys.argv[1]), sys.argv[2]
    if '--so-gabarito' in sys.argv:
        ent = json.load(open(sys.argv[sys.argv.index('--so-gabarito') + 1]))
        g = gabarito(ent['numeros']); json.dump({**ent, "calculado_em": datetime.datetime.now(TZ).isoformat(timespec='seconds'), "gabarito": g},
                                                open(saida, 'w'), ensure_ascii=False, indent=1); sys.exit()
    desde = datetime.date.today() - datetime.timedelta(days=120)
    curto = lambda i: len(i.get('body') or '') <= 4000
    iss = sorted((i for i in busca('is:issue', desde) if curto(i)), key=lambda i: i['number'])
    prs = sorted((i for i in busca('is:pr is:merged', desde) if curto(i)), key=lambda i: i['number'])
    grupos = {
        "H1": [i for i in iss if i['state'] == 'open' and not i['assignees']],
        "H2": [i for i in iss if i['state'] == 'open' and i['assignees']],
        "H3": iss,
        "H4": prs,
        "H5": [i for i in iss if i['state'] == 'closed'],
    }
    rng = random.Random(sem)
    nums = [rng.choice(grupos[k])['number'] for k in ("H1", "H2", "H3", "H4", "H5")]
    out = {"repo": REPO, "semente": sem, "desde": desde.isoformat(), "populacao": {k: len(v) for k, v in grupos.items()}, "numeros": nums,
           "calculado_em": datetime.datetime.now(TZ).isoformat(timespec='seconds'), "gabarito": gabarito(nums)}
    json.dump(out, open(saida, 'w'), ensure_ascii=False, indent=1)
    print(out['populacao'], nums)
