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

## Como o código está organizado

| Módulo | O que faz |
| --- | --- |
| `RedeSocial.Accounts` | Contas básicas e verificadas pelo gov.br, com apelido, selo e impressão digital do CPF |
| `RedeSocial.Social` | Posts, curtidas, salvamentos, seguidores, views e as ligações do grafo para o motor |
| `RedeSocial.Feed` | Junta os candidatos e pede a ordem ao motor em Rust. Sem o motor, mostra só quem a pessoa segue, por data |
| `RedeSocial.Ads` | Anúncios nos shorts e nos vídeos, rateio entre criadores e painel do criador |
| `RedeSocial.Engine` | Cliente HTTP do motor (`services/engine-server`) |
| `RedeSocial.Transparency` | O que a página de transparência mostra |
| `RedeSocial.Demo` | Pessoas de exemplo, gov.br simulado e dados de demonstração |

As rotas da API estão em `lib/rede_social_web/router.ex`. As de gov.br simulado e pessoas de exemplo só existem com `demo_mode` ligado, que fica desligado em produção.

## Dados de demonstração

Os dados de exemplo são criados no primeiro `mix setup`, inclusive os vídeos, gerados com o ffmpeg que vem na imagem de desenvolvimento. Para começar do zero, mesmo com o backend rodando:

```bash
docker compose exec backend mix demo.reset
```

## Configuração

| Variável | Para quê |
| --- | --- |
| `DB_HOST` | Host do PostgreSQL em dev e teste (padrão: `localhost`) |
| `ENGINE_URL` | Endereço do motor de feed e anúncios (padrão: `http://localhost:7070`) |
| `DATABASE_URL` | Banco em produção |
| `SECRET_KEY_BASE` | Chave do Phoenix em produção |
| `CPF_FINGERPRINT_KEY` | Chave da impressão digital do CPF em produção. No piloto ela vem de um cofre de hardware (HSM) |
