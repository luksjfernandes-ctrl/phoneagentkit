"""Bateria B v4 · transcreve tarefas-v4.md para o v3.json que o agente congelado lê (Documents/BateriaB, fora do git),
um arquivo por bloco, e faz o sorteio do G pela regra da tarefa. Congelado junto com o corretor, antes da rodada 1.

Uso:
  python3 transcrever_v4.py I <saida.json>
  python3 transcrever_v4.py H <gabarito_h4.json> <saida.json>
  python3 transcrever_v4.py G <semente> <meta-gmail.json> <saida.json> <sorteio-g.json>
  python3 transcrever_v4.py A <gabarito_h4.json> <saida.json>

Notas de transcrição (o esquema é o do V3.swift congelado; nada aqui muda o agente):
- I: `fatos` e `proibidas` vão crus e minúsculos, para a nota secundária do app; a nota oficial é a do corretor_v4.py.
- G: as frases já saem com o parâmetro sorteado escrito (sem marcador), e o `q` do gabarito usa endereço e epoch fixos.
- A: `alvo` calculado aqui, independente do agente: sexta 23/10 10:00, hoje 20/10 09:00 e quinta 22/10 16:00.
  A I4.1 entra no I com o id interno "I3.1", o único que o congelado usa para ler a origem do A3.
"""
import datetime, json, random, re, sys, unicodedata
sys.path.insert(0, __import__('os').path.dirname(__file__))
from corretor_v4 import PAGINAS

IDS = {'I4.1': '3ff2d8a7-6b8b-81a3-bae7-fc582f54ad92', 'I4.2': '3ff2d8a7-6b8b-815a-bfe3-da2573e45a7d',
       'I4.3': '3ff2d8a7-6b8b-819f-8a74-c0a2a9e787a6', 'I4.4': '3ff2d8a7-6b8b-81ba-b5eb-ce91166da678',
       'I4.5': '3ff2d8a7-6b8b-816e-98b7-f50aa6ea0918'}
TZ = datetime.timezone(datetime.timedelta(hours=-3))

def item_i(tid, rotulo=None):
    p = PAGINAS[tid]
    return {"id": rotulo or tid, "pagina": IDS[tid], "pedido": "resume essa página",
            "fatos": [[a.replace(' ', '/') if re.fullmatch(r'\d+ \d+', a) else a for a in alt] + alt for alt in p['fatos']],
            "minimo_fatos": 2, "proibidas": p['proibidas']}

def h_arq(gab):
    g = gab['gabarito']
    T = lambda **k: {**{"n": None, "titulo": None, "estado": None, "responsaveis": None, "rotulos": None,
                        "merged": None, "draft": None, "rotulo": None, "total": None}, **k}
    return {"repo": gab['repo'], "rotulos_do_repo": [], "tarefas": [
        T(id="H1", chip="responsavel", frase=f"quem é o responsável pela #{g['H1']['n']}?", n=g['H1']['n'], responsaveis=g['H1']['responsaveis'], estado=g['H1']['estado']),
        T(id="H2", chip="responsavel", frase=f"quem cuida da #{g['H2']['n']}?", n=g['H2']['n'], responsaveis=g['H2']['responsaveis'], estado=g['H2']['estado']),
        T(id="H3", chip="autor", frase=f"who opened issue #{g['H3']['n']}?", n=g['H3']['n'], titulo=g['H3']['titulo']),
        T(id="H4", chip="resumir_pr", frase=f"resume a PR #{g['H4']['n']}", n=g['H4']['n'], titulo=g['H4']['titulo'], estado=g['H4']['estado'], merged=g['H4']['merged']),
        T(id="H5", chip="closed_at", frase=f"quando a #{g['H5']['n']} foi fechada?", n=g['H5']['n'], titulo=g['H5']['titulo'], estado=g['H5']['estado']),
        T(id="H6", chip="contar_draft", frase="quantas PRs abertas estão em rascunho?", draft=True, total=g['H6']['total']),
    ]}

STOP = set("""about after again agora ainda antes assim being below cada coisa como dessa desse desta deste depois email emails
entre essa esse estao from have hello hoje junto mais mesmo minha muito nossa nosso novas novos nunca onde outra outro para pelas
pelos pode quando quem sobre sua suas their there these this those todas todos uma umas voce what when where which while with
would your sobre seus estes estas""".split())

def endereco(r):
    m = re.search(r'<([^>]+)>', r or ''); return (m.group(1) if m else (r or '')).strip().lower()
def nome(r):
    m = re.match(r'\s*"?([^"<]*?)"?\s*<', r or ''); return (m.group(1).strip() if m else '') or endereco(r)
def dominio(r): return endereco(r).split('@')[-1]
def fold(s): return ''.join(c for c in unicodedata.normalize('NFKD', s.lower()) if not unicodedata.combining(c))

def sortear_g(sem, meta):
    agora = meta['coletado_em']; ms = [m for m in meta['mensagens'] if m['ts']]
    dia0 = datetime.datetime.fromtimestamp(agora, TZ).replace(hour=0, minute=0, second=0, microsecond=0)
    seg0 = dia0 - datetime.timedelta(days=dia0.weekday())
    ontem0, hoje0 = int((dia0 - datetime.timedelta(days=1)).timestamp()), int(dia0.timestamp())
    d7, d8, d14 = agora - 7 * 86400, agora - 8 * 86400, agora - 14 * 86400
    rng, s, nao_aplicavel = random.Random(sem), {}, []
    # G1: nome de exibição de um endereço com >= 2 e-mails em 14 dias e nome único entre os remetentes
    por_end = {}
    for m in ms:
        if m['ts'] >= d14: por_end.setdefault(endereco(m['remetente']), []).append(m)
    nomes = {}
    for m in ms: nomes.setdefault(nome(m['remetente']).lower(), set()).add(endereco(m['remetente']))
    pop1 = sorted(((e, v) for e, v in por_end.items() if len(v) >= 2 and len(nomes[nome(v[0]['remetente']).lower()]) == 1), key=lambda x: (x[0], min(m['id'] for m in x[1])))
    e1, v1 = rng.choice(pop1); s['G1'] = {"nome": nome(v1[0]['remetente']), "endereco": e1, "k": rng.choice([3, 5, 10]), "populacao": len(pop1)}
    # G3: domínio com >= 1 e-mail entre 8 e 30 dias e zero desde segunda 00:00
    doms_sem = {dominio(m['remetente']) for m in ms if m['ts'] >= seg0.timestamp()}
    pop3 = sorted({dominio(m['remetente']) for m in ms if m['ts'] < d8} - doms_sem)
    if pop3: s['G3'] = {"dominio": rng.choice(pop3), "populacao": len(pop3)}
    else: nao_aplicavel.append('G3')
    # G4: token alfabético >= 5 letras, fora das stopwords, em 1 a 3 assuntos dos últimos 7 dias
    cont = {}
    for m in ms:
        if m['ts'] >= d7:
            for w in set(re.findall(r'[a-z]+', fold(m['assunto']))):
                if len(w) >= 5 and w not in STOP: cont[w] = cont.get(w, 0) + 1
    pop4 = sorted(w for w, c in cont.items() if 1 <= c <= 3)
    s['G4'] = {"palavra": rng.choice(pop4), "populacao": len(pop4)}
    # G5: assunto único nos últimos 7 dias, com >= 3 palavras (ordem por data, desempate id)
    sem7 = [m for m in ms if m['ts'] >= d7]
    freq = {}
    for m in sem7: freq[m['assunto'].strip()] = freq.get(m['assunto'].strip(), 0) + 1
    pop5 = sorted((m for m in sem7 if freq[m['assunto'].strip()] == 1 and len(m['assunto'].split()) >= 3 and '"' not in m['assunto']),
                  key=lambda m: (m['ts'], m['id']))
    m5 = rng.choice(pop5); s['G5'] = {"assunto": m5['assunto'].strip(), "populacao": len(pop5)}
    # G6: domínio com >= 1 e-mail ontem
    pop6 = sorted({dominio(m['remetente']) for m in ms if ontem0 <= m['ts'] < hoje0})
    if pop6: s['G6'] = {"dominio": rng.choice(pop6), "populacao": len(pop6)}
    else: nao_aplicavel.append('G6')
    s['_janelas'] = {"agora": agora, "d7": d7, "segunda0": int(seg0.timestamp()), "ontem0": ontem0, "hoje0": hoje0}
    s['_nao_aplicavel'] = nao_aplicavel
    return s

def g_tarefas(s):
    j = s['_janelas']; out = []
    g1 = s['G1']
    out.append({"id": "G1", "chip": "contar", "frase": f"quantos e-mails o {g1['nome']} mandou nos últimos {g1['k']} dias?",
                "q": f"from:{g1['endereco']} after:{j['agora'] - g1['k'] * 86400}", "tipo": "contagem"})
    out.append({"id": "G2", "chip": "mais_antigo_nao_lido", "frase": "qual é o e-mail não lido mais antigo dos últimos 7 dias?",
                "q": f"is:unread after:{j['d7']}", "tipo": "mais_antigo_nao_lido"})
    if 'G3' in s:
        out.append({"id": "G3", "chip": "existe", "frase": f"chegou alguma coisa de {s['G3']['dominio']} nesta semana?",
                    "q": f"from:{s['G3']['dominio']} after:{j['segunda0']}", "tipo": "existe"})
    out.append({"id": "G4", "chip": "quando", "frase": f"when did the last email with '{s['G4']['palavra']}' in the subject arrive?",
                "q": f"subject:({s['G4']['palavra']}) after:{j['d7']}", "tipo": "quando"})
    out.append({"id": "G5", "chip": "quem_mandou", "frase": f"quem mandou o e-mail '{s['G5']['assunto']}'?",
                "q": f'subject:"{s["G5"]["assunto"]}" after:{j["d7"]}', "tipo": "quem_mandou"})
    if 'G6' in s:
        out.append({"id": "G6", "chip": "existe", "frase": f"recebi alguma coisa de {s['G6']['dominio']} ontem? quantos?",
                    "q": f"from:{s['G6']['dominio']} after:{j['ontem0']} before:{j['hoje0']}", "tipo": "existe"})
    return out

def a_tarefas(gab):
    n = gab['gabarito']['H2']['n']
    prob_a3 = ['9480', '9 480', '9.480', '55021', '2297', 'lumen', 'chave de recebimento', 'agência', 'agencia', 'titular', 'avisar quem pediu', 'quitação', 'quitacao']
    return [
        {"id": "A1", "frase": "cobrar o responsável sexta às 10h", "ref": f"issue #{n}", "origem": "H2", "alvo": "2026-10-23 10:00", "deve": "cobrar o responsável", "proibidas": ["transferir"]},
        {"id": "A2", "frase": "responder esse e-mail hoje às 9h", "ref": "e-mail lido", "origem": "G5", "alvo": "2026-10-20 09:00", "deve": "responder esse e-mail", "proibidas": ["transferir"]},
        {"id": "A3", "frase": "revisar a memória da reunião quinta às 16h", "ref": "página I4.1", "origem": "I3.1", "alvo": "2026-10-22 16:00", "deve": "revisar a memória da reunião", "proibidas": prob_a3},
    ]

if __name__ == '__main__':
    b = sys.argv[1]
    if b == 'I':
        out = {"I": [item_i(t) for t in PAGINAS]}; dest = sys.argv[2]
    elif b == 'H':
        out = {"H": h_arq(json.load(open(sys.argv[2])))}; dest = sys.argv[3]
    elif b == 'G':
        sem, meta = int(sys.argv[2]), json.load(open(sys.argv[3]))
        s = sortear_g(sem, meta)
        out = {"semente": sem, "G": g_tarefas(s)}; dest = sys.argv[4]
        json.dump({"semente": sem, **s}, open(sys.argv[5], 'w'), ensure_ascii=False, indent=1)
        print('G populações:', {k: v.get('populacao') for k, v in s.items() if not k.startswith('_')}, 'não aplicável:', s['_nao_aplicavel'])
    elif b == 'A':
        gab = json.load(open(sys.argv[2]))
        out = {"H": h_arq(gab), "I": [item_i('I4.1', rotulo='I3.1')], "A": a_tarefas(gab)}; dest = sys.argv[3]
    json.dump(out, open(dest, 'w'), ensure_ascii=False, indent=1)
    print('gravado', dest)
