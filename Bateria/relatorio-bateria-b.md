# Bateria B · relatório (parcial, 24/09/2026)

Pergunta da bateria: dá para construir sobre o modelo local da Apple um app gratuito de assistente que funcione como produto? Spec: `SecondLucas/C01 Claude Obsidian/04 Projetos & Specs/2026-09-24__spec__bateria-b-meta-muse-local.md`.

**Estado:** B4 e B6(a) rodados no **Mac M4** (referência). Falta o **iPhone 17**, que é o aparelho principal (agenda com a sessão coordenadora). B1, B2, B3 e B5 dependem do Lucas: ver `PENDENCIAS-LUCAS.md`. Ainda não há veredito, porque a régua da spec exige B1, B2, B4 e B5.

## Método e ressalvas declaradas

- **Agente congelado no commit `b6cbf1d`**, antes da 1ª rodada. O iPhone roda o mesmo commit.
- **Quem escreveu o agente leu as tarefas cegas** (`tarefas-v1.md`) antes de congelar, porque precisou implementar o gabarito por código. O desenho do agente (menu de fontes: agenda, lembretes, contatos, fotos, datas) segue os domínios que a spec lista para o B4. As instruções e os menus são genéricos, sem frase tirada das tarefas.
- **Gabarito por código**, calculado no mesmo processo e a partir da mesma loja do EventKit, dos Contatos e do PhotoKit, no instante de cada tarefa. O contato e a lista são sorteados com semente registrada (`1790285074`), só entre contatos com telefone e listas com lembrete aberto.
- **Correções do corretor depois da rodada 1**, sem mudar o agente, em `rescore.py`:
  1. O corretor tira emoji e pontuação dos dois lados, porque o modelo remove emoji dos títulos.
  2. Um título conta como citado quando as palavras dos 4 primeiros termos aparecem na resposta, em qualquer ordem. Exemplo: "Equipe — Reunião Geral" bate com "reunião geral da equipe".
  3. O código entre colchetes no início do título ("[ABC-123]") é ignorado.
  4. No B4.4, todo telefone exibido tem de ser do contato sorteado. O número de outra pessoa conta como resposta **perigosa**, e a tarefa reprova mesmo com 2/3 certas.

  **Trajetória do placar do kit (a v2 fica em 2/10 em todas as versões):**

  | Corretor | Kit |
  |---|---|
  | original | 5/10 |
  | + regras 1 e 2 | 7/10 |
  | + regra 3 | 9/10 |
  | + regra 4 | **8/10** |

  **Notas lado a lado:**

  | Corretor | Kit | v2 |
  |---|---|---|
  | original | 5/10 (15/30) | 2/10 (7/30) |
  | ajustado | 8/10 (26/30) | 2/10 (7/30) |

  As 4 regras foram escritas depois de ver as falhas do kit. A sessão coordenadora as ratificou em 24/09. As mesmas regras valem para a v2, que foi reavaliada e ficou em 2/10 nas duas versões. A regra 4 é permanente. O `rescore.py` fica congelado com elas antes da rodada do iPhone.

  As notas do corretor original ficam nos brutos (campo `nota`); as novas, em `nota2`.
- **Dois agentes nas mesmas tarefas:**
  - **kit:** padrão do PhoneAgentKit, só leitura. O modelo escolhe num `NumberedMenu`, o código busca e rotula (`LabeledRecord`), e o modelo redige a partir dos fatos (`PinnedSource.answer`). As datas saem do código.
  - **v2:** linha de base, com tool calling livre e as instruções de 23/09. A única mudança é "responda no idioma do pedido" (B7).
- **Onde ficam os dados:** os brutos estão em `Bateria/brutos/`, fora do git. Este relatório não traz nomes, títulos nem telefones.

## B4 · nativo sem conector (Mac M4, AFM 3 Core Advanced, contexto 8.192)

Régua: ≥ 8/10 tarefas. Uma tarefa passa com 2/3 ou 3/3 rodadas certas.

| Tarefa | kit | v2 |
|---|---|---|
| B4.1 amanhã | ✓✓✓ | ✗✗✗ |
| B4.2 próximo compromisso | ✓✓✓ | ✗✗✗ |
| B4.3 lembretes atrasados | ✓✓✓ | ✗✗✗ |
| B4.4 telefone de {contato} | ✓✗✓ **perigosa** | ✓✓✓ |
| B4.5 sexta à tarde | ✗✗✗ | ✗✗✗ |
| B4.6 weekend (EN) | ✓✓✓ | ✓✗✗ |
| B4.7 contagem da {lista} | ✓✓✓ | ✓✓✓ |
| B4.8 última foto | ✓✓✓ | ✗✗✗ |
| B4.9 due today (EN) | ✓✓✓ | ✗✗✗ |
| B4.10 dia da semana do dia 10 | ✓✓✓ | ✗✗✗ |
| **Total** | **8/10 (26/30)** | **2/10 (7/30)** |

- **Latência:** o kit teve p50 de 2,5 s, p95 de 7,7 s e máximo de 8,3 s; a v2, p50 de 2,3 s e p95 de 7,3 s.
- **Idioma (B7):** o kit acertou 21/24 em pt e 6/6 em en. A régua exige diferença de no máximo 1 tarefa, e o kit ficou dentro dela.

**Resultado:** o kit fica em 8/10 e passa na régua (≥ 8/10), exatamente no limite.

**Erros por padrão**

- **kit, B4.4 R2 (perigosa):**
  - O modelo extraiu só o primeiro nome do contato, e a busca achou mais de uma pessoa.
  - A resposta mostrou um telefone que não é do contato sorteado.
  - O corretor original deu "ok" porque procura o número certo em qualquer ponto da resposta. Além disso, o mascaramento do app funde dois números vizinhos num só final, e com isso a prova do que o modelo escreveu se perdeu.
  - Lição para a v2 das tarefas: o código deve exigir um único contato, ou montar um menu quando houver homônimos.

- **kit, B4.5 ("sexta à tarde"):**
  - O menu escolheu o dia inteiro de sexta.
  - O modelo respondeu com um evento das 20h e não recortou a tarde.
  - Deixou de fora o evento de vários dias que cobre a tarde.
  - O menu não tem a opção "período do dia". O agente não foi corrigido, porque ajuste só conta numa v2 com tarefas novas.
- **kit, idioma:** o B4.8 foi perguntado em pt e respondido em en ("The most recent photo was taken on terça-feira…"). A resposta está certa, mas misturou os idiomas. O corretor não pune isso.
- **v2, falhas estruturais (a ferramenta não dava o dado):**
  - B4.10: a v2 só tinha uma tabela de 8 dias e nenhuma ferramenta de data, como em 23/09. Não tinha como acertar.
  - A ferramenta `ultima_foto` exige um argumento fictício, o que pode ter inibido a chamada.
  - `ler_lembretes` mostra hora também nos lembretes que só têm data.
- **v2, falhas do modelo e respostas perigosas (dado inventado):**
  - B4.8: inventou a data da última foto sem chamar a ferramenta ("18:25 de hoje", "2025-12-03 às 14:30", "[data e hora]").
  - B4.10: errou o dia da semana nas 3 rodadas, com dias diferentes em cada uma.
  - B4.3 e B4.9: respondeu "não há lembretes" com lembretes na lista.
  - B4.1: em vez de responder, devolveu as chamadas de ferramenta como texto.
- **Contraste:** kit 8/10 × v2 2/10. Sem o B4.10, que era impossível para a v2 por construção, fica kit 7/9 × v2 2/9. Esta é a versão para citar. É o mesmo achado do Notion (3/9 × 24/30), agora nos dados nativos.

## B6(a) · cota (Mac M4)

150 chamadas de 1 etapa, uma a cada 18 s, com o app aberto e `caffeinate`, das 17h39 às 18h24.

| rateLimited | outros erros | p50 | p95 | máximo | > 60 s |
|---|---|---|---|---|---|
| **0** | 0 | 1,95 s | 6,75 s | 252 s | 3 |

- **Régua:** 0 bloqueios ✓; p95 ≤ 10 s ✓.
- **Chamadas acima de 60 s:**

  | Chamada | Horário | Duração |
  |---|---|---|
  | nº 55 | 17h55 | 205 s |
  | nº 69 | 17h59 | 252 s |
  | nº 91 | 18h06 | 160 s |

  A nº 70 levou 36 s. O Mac não dormiu. Nada verificou que o app ficou em primeiro plano durante as 45 min. O `caffeinate` só impediu o repouso.
- **Possível contaminação, não conclusão:** às 17h55 havia um `xcodebuild` de testes de outra sessão rodando no Mac, e a perícia de outra sessão, que usa o modelo local, só foi pausada por volta das 18h03, quando combinamos a exclusividade. A nº 91 (18h06) veio depois disso. Se o iPhone, com exclusividade desde o início, também tiver chamadas acima de 60 s, a lentidão é do sistema e não da concorrência.

## Falta

- iPhone 17: B4 (kit e v2) e B6(a), no commit `b6cbf1d`.
- B6(b), com 20 chamadas via App Intent com o app em segundo plano: não está no harness ainda.
- B1, B2, B3 e B5: `PENDENCIAS-LUCAS.md`.
