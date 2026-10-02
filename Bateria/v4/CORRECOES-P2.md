# Correções locais da revisão do PR #5

O motor `V3` agora é compilado pelo alvo SwiftPM `BateriaCore`, além de continuar no app Xcode. `Saida` foi movido para seu próprio arquivo para permitir essa compilação. Os testes de regressão estão em `Tests/BateriaCoreTests/V3RegressionTests.swift`; usam mensagens sintéticas, respostas MCP em memória e gravação por closure. Não chamam conectores, inferência do modelo, EventKit nem contas reais.

| Achado | Correção | Regressão |
| --- | --- | --- |
| 1. Texto suspeito no lembrete | Filtro de entrada e guarda de saída antes do truncamento; referência de uma linha, até 120 caracteres. Texto totalmente rejeitado vira referência neutra. | `referenciaNaoPropagaInstrucaoNaGravacao`, `referenciaFiltraAntesDeTruncarEProtegeLiteral` |
| 2. Aviso de horário passado | A proposta mantém a decisão e seu aviso. Confirmação exige o texto inteiro apresentado; o harness apresenta antes de simular o toque. | `dataPassadaExigeConfirmacaoComAviso`, `harnessApresentaAvisoAntesDaGravacao` |
| 3. Falta da origem | Origem definida exige leitura não vazia; falta gera erro antes de consultar/gravar lembretes. Referência literal vale somente sem origem. | `origemObrigatoriaAusenteOuVaziaFalha` |
| 4. G5 referencia outro e-mail | A rodada guarda a seleção do agente por tarefa; A reutiliza G5. Se A rodar sozinho, executa o pedido de G5. Se G5 falhar ou não selecionar nada, não usa outra mensagem. | `origemG5ReutilizaContratoSelecionado` |
| 5. Issue usa endpoint de PR | Os chips de metadados escolhem issue/PR pelo pedido, com endpoint e chave numérica correspondentes. | `metadadosEscolhemTipoPeloPedido`, `metadadosExecutamEndpointCorreto` |
| 6. Autor de outro objeto | Seleciona o objeto pelo número pedido e lê somente `user.login`. | `autorDaPRIgnoraResponsavelRevisorEDono`, `metadadosExecutamEndpointCorreto` |
| 7. Corretor aceita valor errado | Gabarito H inclui `autor` e `closed_at`; compara o valor inteiro. Campo esperado ausente gera erro; estado aberto permite `closed_at` nulo. | `corretorAutorRejeitaDesconhecidoEOOutroUsuario`, `corretorFechamentoComparaDataEEstadoAberto` |
| 8. Busca G copia gabarito | Os três chips novos extraem remetente, assunto e limites do período da frase. A função de busca do agente não recebe `q` do gabarito. | `novosChipsBuscamPelaFrase` (três chips), `periodoInvalidoNaoAmpliaConsulta` |
| 9. Corretor espera mais recente | Seleciona o mais antigo entre não lidos, inclusive quando o tipo do gabarito é `assunto`. Busca desse gabarito usa teto de 500, em vez do teto de uma mensagem. | `corretorMaisAntigoFiltraLidosEOrdena` (três tipos) |

## Gabarito H

Para tarefas `autor`, inclua `"autor": "login-esperado"`. Para tarefas `closed_at` de itens fechados, inclua `"closed_at": "2031-01-09T12:00:00Z"` (timestamp completo). Para itens abertos, inclua `"estado": "open"`. Não reutilize um gabarito antigo sem esses valores: ele produzirá erro explícito em vez de aprovar por palavras-chave. O gerador `Bateria/v3/gabarito_h3.py` agora preserva também o timestamp completo de H5; não foi executado contra o GitHub nesta correção.

## Validação no sandbox

As dependências já presentes no cache local foram copiadas para `.build`; não houve download nem atualização. Com os caches dentro da árvore, foi executado:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test \
  --disable-sandbox --skip-update --disable-automatic-resolution \
  --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" \
  --security-path "$PWD/.build/security" --scratch-path "$PWD/.build" \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/clang-module-cache" -j 2
```

Resultado: **64 testes passaram** (50 do kit + 14 da bateria, com casos parametrizados adicionais). O flag `--disable-sandbox` evita a tentativa do SwiftPM de criar um sandbox dentro do sandbox do executor, que falha com `sandbox_apply: Operation not permitted`. Os caches permanecem nos diretórios autorizados.

A validação cobre o código real do motor no macOS e suas fronteiras determinísticas. UI do iPhone, inferência dos parâmetros pelo modelo, conectores remotos e gravação real no EventKit não foram exercitados.
