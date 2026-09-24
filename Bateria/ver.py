import json,glob,os,sys
f=sorted(glob.glob(os.path.expanduser('~/Documents/BateriaB/b4-*.json')))[-1];d=json.load(open(f))
print(d['aparelho'],d['commit'],d['semente'],len(d['resultados']))
for r in d['resultados'][int(sys.argv[1]) if len(sys.argv)>1 else 0:]:
    print(r['modo'],r['rodada'],r['tarefa'],round(r['segundos'],1),r['nota'],' '.join(r['trilha'])[:80],'|',r['resposta'][:120].replace('\n',' '))
