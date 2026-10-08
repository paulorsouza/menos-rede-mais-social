# RFCs: como as regras da rede mudam

Uma RFC é uma proposta escrita de mudança nas regras da rede. Toda mudança no feed, nos parâmetros de `params/`, na divisão do dinheiro dos anúncios, na moderação ou nos dados que guardamos sobre as pessoas passa por aqui antes de virar código.

## Passo a passo

1. Copie o [modelo](0000-modelo.md) para um arquivo novo, `NNNN-titulo-curto.md`, com o próximo número livre.
2. Abra um pull request só com a RFC. A discussão acontece ali, em público.
3. A RFC fica aberta para comentários por 30 dias (prazo proposto no plano). Correções urgentes de segurança podem entrar antes e ser explicadas depois.
4. O conselho decide. Enquanto o conselho não existir, as pessoas mantenedoras decidem, e a decisão fica registrada no próprio pull request.
5. Aprovada, a RFC entra no repositório e o código que a implementa pode ser enviado. Se mexer em `params/`, o `version` do arquivo sobe.

Uma RFC recusada também entra no repositório, com o motivo. Isso evita que a mesma discussão recomece do zero.
