# -rede+social

Uma rede social pública, de código aberto e sem fins lucrativos, pensada para o Brasil. O governo paga a infraestrutura, mas a rede é de quem usa. O porquê está no [manifesto](MANIFESTO.md), e o como está no [plano inicial](docs/plano-inicial.md). As regras que nenhuma decisão pode quebrar estão nas [regras pétreas](specs/regras-petreas.md).

Por enquanto este repositório é um esqueleto. Já tem a estrutura das três partes do sistema, as regras de feed e de pagamento a criadores implementadas e testadas, e o básico de cada aplicação para começar a Fase 1 (o protótipo).

## Como o repositório está organizado

```
specs/regras-petreas.md  a constituição do projeto: o que nunca pode mudar
apps/web/                front em React (Vite + TypeScript)
apps/backend/            backend em Elixir (Phoenix + Ecto + PostgreSQL)
services/                serviços em Rust (workspace Cargo)
  feed-engine/           os modos de feed, determinísticos e auditáveis
  ads-engine/            exibições, faixas de pagamento e rateio dos shorts
params/                  parâmetros públicos do feed e dos anúncios
proto/                   contratos gRPC entre o backend e os serviços em Rust
docs/plano-inicial.md    o plano: produto, dinheiro, arquitetura, governança e fases
docs/rfcs/               propostas de mudança nas regras da rede
```

O backend em Elixir atende o app e a web e coordena o resto. O que precisa ser auditado (feed e anúncios) e o processamento pesado de vídeo ficam em Rust. Os números que mexem no feed e no dinheiro de criadores não ficam espalhados no código: estão em `params/`, num formato que qualquer pessoa consegue ler, e só mudam por RFC.

## Rodando na sua máquina

Você vai precisar de Node 20.19 ou mais novo, Rust 1.85 ou mais novo e Docker. Elixir é opcional, porque o backend também roda dentro do Docker. Quem usa Nix pode entrar no ambiente com `nix develop` (o `flake.nix` ainda não foi testado).

Banco e backend, sem instalar Elixir:

```bash
docker compose up
```

Se a porta 5432 já estiver em uso na sua máquina, troque a porta do banco:

```bash
DB_PORT=5433 docker compose up
```

Front (abre em http://localhost:5173 e fala com o backend em :4000):

```bash
cd apps/web
npm install
npm run dev
```

Serviços em Rust:

```bash
cd services
cargo test
```

Mais detalhes do backend, inclusive como rodar com Elixir instalado, estão em [apps/backend/README.md](apps/backend/README.md).

## O que já funciona

- **Motor de feed** (`services/feed-engine`): na bolha, furando a bolha, meio a meio, por data e ranking público. Cada item vem com o motivo de ter aparecido, e o mesmo conjunto de dados sempre gera o mesmo feed.
- **Motor de anúncios** (`services/ads-engine`): conversão de horas compradas em exibições, pagamento por faixas decrescentes (calculado como no imposto de renda, então crescer nunca diminui o ganho) e rateio dos shorts por tempo assistido, sem perder centavo no arredondamento.
- **Backend** (`apps/backend`): `GET /api/health` e o cadastro de contas com apelido, selo de verificado e impressão digital do CPF (o número em si não é guardado).
- **Front** (`apps/web`): tela inicial com as seções, o seletor de modo de feed e o aviso de backend no ar.

## Próximos passos (Fase 1)

- Login gov.br em ambiente de teste (OpenID Connect).
- Posts de texto curto e de fotos, e o feed por data.
- Servidores gRPC em Rust a partir dos contratos em `proto/`.
- Fixar as actions do CI por hash de commit.

## Contribuindo

Leia o [CONTRIBUTING.md](CONTRIBUTING.md). Se você achou uma falha de segurança, não abra issue pública: siga o [SECURITY.md](SECURITY.md).

## Licença

Ainda não foi escolhida. A proposta é a AGPL-3.0, que obriga quem rodar uma versão modificada da rede como serviço a publicar o código. Enquanto a licença não estiver definida, o código não pode ser reutilizado por terceiros.
