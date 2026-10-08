# Backend (Elixir + Phoenix)

API da -rede+social. Cuida das contas, do login gov.br, do tempo real (notificações e chat de live), das filas de tarefas e dos pagamentos, e conversa com os serviços em Rust por gRPC.

## Rodando sem Elixir instalado

Na raiz do repositório:

```bash
docker compose up
```

Isso sobe o PostgreSQL e o backend. A API fica em http://localhost:4000, e dá para testar com `curl http://localhost:4000/api/health`. Se a porta 5432 estiver ocupada, use `DB_PORT=5433 docker compose up`.

Para rodar os testes pelo Docker:

```bash
docker compose run --rm -e MIX_ENV=test backend sh -c "mix local.hex --force && mix local.rebar --force && mix deps.get && mix test"
```

## Rodando com Elixir instalado

Suba só o banco (`docker compose up -d db` na raiz) e, nesta pasta:

```bash
mix setup
mix phx.server
```

Testes:

```bash
mix test
```

## O que já existe

- `GET /api/health`: diz se o backend e o banco estão no ar.
- `RedeSocial.Accounts`: contas básicas e verificadas pelo gov.br, com apelido, selo de verificado e impressão digital do CPF. O CPF em texto não é guardado.

## Configuração

| Variável | Para quê |
| --- | --- |
| `DB_HOST` | Host do PostgreSQL em dev e teste (padrão: `localhost`) |
| `DATABASE_URL` | Banco em produção |
| `SECRET_KEY_BASE` | Chave do Phoenix em produção |
| `CPF_FINGERPRINT_KEY` | Chave da impressão digital do CPF em produção. No piloto ela vem de um cofre de hardware (HSM) |
