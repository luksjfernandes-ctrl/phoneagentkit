# Preparação da bateria v4 — 20/10/2026

Verificação realizada sobre o commit `c0994819253d94fb9434ab45e0b8ca71a24d7406`
do PR #5, sem abrir tarefas cegas novas nem chamar o agente.

- Os 31 hashes do manifesto conferem com os arquivos da branch.
- Nenhum fonte, teste, roteiro ou hash congelado foi alterado nesta verificação.
- Verificador reproduzível: `python3 scripts/verify-v4-freeze.py`.
- A bateria v4 continua sem resultados; os números de v2/v3 não são resultados de v4.

## Dependências da execução real

Este ambiente é Linux e não dispõe de Swift, Xcode, Foundation Models ou aparelho
Apple. O pacote declara iOS/macOS 26.4. Não é possível medir o comportamento do
modelo Apple aqui, nem substituir essa medição por uma simulação.

No aparelho/Mac de teste, seguir `Bateria/v4/ROTEIRO.md`: conferir o congelamento,
registrar versão do modelo/fuso/semente, conferir disponibilidade do modelo e
preparar a sessão. Tarefas cegas novas e gabaritos devem receber hash antes da
primeira chamada ao agente; não afinar o agente com a bateria anterior.

O token Composio precisa ser renovado antes dos blocos G, H e A; I usa o conector
Notion. Se houver login pendente, registrar a dependência, sem guardar token,
corpo de e-mail ou documento pessoal nos artefatos. Gravações do bloco A seguem
o fluxo de confirmação da bateria.

Esta entrega acrescenta apenas documentação e verificação de integridade. Não
declara aprovação funcional, execução dos testes Swift ou sucesso da bateria.
