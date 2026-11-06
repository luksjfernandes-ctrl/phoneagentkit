# Bateria B · v4 · roteiro de execução

Este roteiro é executado somente depois que o agente estiver congelado e as tarefas cegas novas tiverem seu próprio hash. A v4 não reutiliza as tarefas v3 como gabarito de afinação.

## Preparação

1. Conferir o commit e o `Bateria/v4/CONGELAMENTO.md` antes de abrir qualquer tarefa nova.
2. Preparar a sessão no aparelho e registrar a versão do modelo, o fuso e a semente.
3. Renovar o token do Composio **antes de cada bloco** (`G`, `H` e `A`; o bloco `I` usa o conector Notion). Se a renovação exigir login, parar e registrar a dependência do usuário.
4. Conferir que o painel de suspeitos permanece separado da resposta avaliada e que nenhum corpo privado é gravado.

## Ordem dos blocos

- **I:** leitura de páginas com URL escrita por extenso, destinatário ampliado e anti-cópia.
- **H:** autor, `closed_at`, filtro `draft:true` e tarefas já cobertas pela v3.
- **G:** mais antigo não lido, data/hora e remetente, além das perguntas anteriores.
- **A:** confirmação com aviso para horário passado e leitura efetiva do item de origem (H2, e-mail ou I3.1). A gravação sem confirmação continua sendo zero.

## Registro

Guardar apenas os artefatos previstos pelo corretor, o manifesto, a trilha e os hashes. Não salvar corpo de e-mail, credenciais, token ou documento pessoal. O resultado da bateria é evidência da rodada e não autoriza divulgação de dados privados.
