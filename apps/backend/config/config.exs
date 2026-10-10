# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :rede_social,
  ecto_repos: [RedeSocial.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :rede_social,
  # Motor de feed e anúncios (services/engine-server).
  engine_url: "http://localhost:7070",
  # Pasta de trabalho: envios em andamento e originais esperando conversão.
  staging_dir: "priv/staging"

# Login Único do gov.br. Fica desligado até ter client_id (config/runtime.exs).
# O gov.br não informa a data de nascimento: sem outra fonte, a conta nasce
# com as proteções de menor de idade (age_fallback).
config :rede_social, :govbr,
  base_url: "https://sso.staging.acesso.gov.br",
  age_fallback: :minor

# Fotos e vídeos prontos. Sem S3 configurado (config/runtime.exs), ficam
# nesta pasta e o próprio backend serve em /media.
config :rede_social, RedeSocial.Storage,
  adapter: RedeSocial.Storage.Local,
  root: "priv/media"

# Lives: a API do servidor de transmissão, o segredo que ele manda ao pedir
# autorização e a pasta onde ele grava (config/runtime.exs no Docker).
config :rede_social, :ao_vivo,
  api: "http://localhost:9997",
  secret: nil,
  recordings_dir: "priv/gravacoes"

# Fila de trabalhos. A fila `video` converte os vídeos; o Cron apaga os
# envios abandonados de hora em hora e as exibições de anúncio vencidas.
config :rede_social, Oban,
  engine: Oban.Engines.Basic,
  repo: RedeSocial.Repo,
  queues: [default: 5, video: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 3600},
    {Oban.Plugins.Cron,
     crontab: [
       {"@hourly", RedeSocial.Uploads.PurgeWorker},
       # De madrugada, apaga as exibições de anúncio que já não contam.
       {"0 7 * * *", RedeSocial.Ads.SlotPurgeWorker},
       # Dia 1, às 6h (UTC), fecha o mês anterior e manda os repasses.
       {"0 6 1 * *", RedeSocial.Payments.CloseMonthWorker}
     ]}
  ]

# Configure the endpoint
config :rede_social, RedeSocialWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: RedeSocialWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RedeSocial.PubSub,
  live_view: [signing_salt: "/KlWitL0"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
