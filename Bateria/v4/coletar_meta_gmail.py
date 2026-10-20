"""Bateria B v4 · sonda de metadados do Gmail para o sorteio do bloco G (tarefas-v4.md, "População do sorteio").
Chama GMAIL_FETCH_EMAILS pelo app (`--exec`, Composio, só leitura), 20 por página, últimos 30 dias.
Guarda SÓ id, remetente, assunto, data (epoch) e não lido. A resposta crua (que traz trecho de corpo) é apagada
a cada página e nunca é impressa. Saída: Bateria/brutos/mac-v4/meta-gmail-<epoch>.json (fora do git).
Uso: python3 -I coletar_meta_gmail.py <runapp.sh>"""
import json, os, subprocess, sys, tempfile, time
RUN = sys.argv[1]
DOC = os.path.expanduser('~/Documents/BateriaB/composio-exec.json')
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'brutos', 'mac-v4')
agora = int(time.time()); desde = agora - 30 * 86400
msgs, token, pag = {}, None, 0
while True:
    args = {"query": f"after:{desde}", "max_results": 20, "include_payload": False, "verbose": False}
    if token: args["page_token"] = token
    if os.path.exists(DOC): os.remove(DOC)
    subprocess.run([RUN, os.path.join(tempfile.gettempdir(), 'meta.log'),
                    'composio exec', '120', '--exec', json.dumps([{"tool_slug": "GMAIL_FETCH_EMAILS", "arguments": args}])],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(DOC): sys.exit(f'página {pag}: exec não gravou resposta')
    d = json.loads(json.load(open(DOC))['texto']); os.remove(DOC)
    r = d['data']['results'][0]['response']['data']
    for m in r.get('messages', []):
        ts = m.get('messageTimestamp') or ''
        try: t = int(time.mktime(time.strptime(ts[:19], '%Y-%m-%dT%H:%M:%S'))) - time.timezone if 'T' in ts else int(ts)
        except Exception: t = None
        msgs[m['messageId']] = {"id": m['messageId'], "remetente": m.get('sender', ''), "assunto": m.get('subject', ''),
                                "ts": t, "ts_txt": ts, "nao_lida": 'UNREAD' in (m.get('labelIds') or [])}
    pag += 1
    token = r.get('nextPageToken')
    print(f'página {pag}: {len(msgs)} mensagens', flush=True)
    if not token or pag >= 40: break
f = os.path.join(OUT, f'meta-gmail-{agora}.json')
json.dump({"coletado_em": agora, "desde": desde, "mensagens": sorted(msgs.values(), key=lambda m: (m['ts'] or 0, m['id']))},
          open(f, 'w'), ensure_ascii=False, indent=1)
print('gravado', f, len(msgs))
