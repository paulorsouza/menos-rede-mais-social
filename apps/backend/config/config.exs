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
  uploads_dir: "priv/uploads",
  # Valor base pago por mil views na primeira faixa, em centavos. Ilustrativo
  # até a decisão do conselho (seção 6 do plano).
  base_cents_per_thousand: 200

# Login Único do gov.br. Fica desligado até ter client_id (config/runtime.exs).
# O gov.br não informa a data de nascimento: sem outra fonte, a conta nasce
# com as proteções de menor de idade (age_fallback).
config :rede_social, :govbr,
  base_url: "https://sso.staging.acesso.gov.br",
  age_fallback: :minor

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
