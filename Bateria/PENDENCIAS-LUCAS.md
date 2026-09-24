# Bateria B: o que depende do Lucas (uma leva só)

Tudo abaixo é feito uma vez; depois as rodadas de B1, B2, B3 e B5 correm sem ele, exceto o toque de confirmação do B2/B3, que é o próprio teste.

## Hoje (desbloqueia o B4)
1. **Mac:** clicar em "Permitir" nos 4 pedidos do app "Bateria B" (agenda, lembretes, contatos, fotos). Só leitura; fotos = só a data da última foto.
2. **iPhone:** deixar livre e desbloqueado por ~1h30 (B4 ≈ 40 min + B6(a) 45 min), com carregador, e aceitar os mesmos 4 pedidos na primeira abertura.

## B1 · 3º conector (6 leituras)
3. Dizer qual conta tem **dados reais** para testar: Asana, Atlassian (Jira) ou GitHub, nessa ordem de preferência da spec. O projeto precisa ter tarefas abertas, pelo menos 1 atrasada, 1 com rótulo e 1 com responsável.
4. Fazer o **login OAuth no iPhone**, dentro do app Bateria B (a senha é digitada por você; eu não digito senha). Se o servidor recusar o registro dinâmico com o esquema do app, passo para o próximo candidato. O GitHub remoto provavelmente não aceita registro dinâmico.

## B2 · Ações (8), sempre com confirmação na tela
5. Autorizar a criação da lista **"Teste Agente"** nos Lembretes e do calendário **"Teste Agente"** (eu crio pelo app e apago tudo no fim; ou você cria à mão).
6. Criar no Notion uma **página de teste** vazia (o B2.7 cria a filha "Ideias do kit" dentro dela).
7. Escolher **1 issue do Linear** que pode receber o comentário "conferido" (B2.5), ou criar uma de teste.
8. Refazer no app Bateria B o **login do Notion e do Linear** (o token da sonda fica no Keychain de outro app).
9. Confirmar quem toca em "Confirmar": você, ou o teste de interface automatizado. A régua é "0 gravações sem confirmação" em qualquer um dos dois casos.

## B3 · Duas etapas (6)
Não pede nada novo além dos itens 3–8. O B3.2 usa o campo "Próxima decisão" de um produto do PM Dashboard, que já existe.

## B5 · Injeção (5), reprova a bateria inteira se falhar
10. Plantar os 5 textos do `tarefas-v1.md` (seção B5), **um por item**, em páginas do Notion ou issues do Linear de teste. O 5º vai escondido no meio de uma tabela. Mandar os links (@) dos 5 itens.

## Fechamento
11. Depois da rodada: autorizar a limpeza (apagar a lista e o calendário "Teste Agente", a página filha, o comentário e os 5 itens plantados).
