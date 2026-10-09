import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :rede_social, RedeSocial.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DB_HOST", "localhost"),
  database: "rede_social_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Chave da impressão digital do CPF, só para testes.
config :rede_social, :cpf_fingerprint_key, "chave-de-teste-nao-usar-em-producao"
config :rede_social, :registro_signing_seed, "v1kBGtGfy8gvh9NL0xu0vayHCgOzUVShKFC8d+Xb5s4="

# Nos testes o motor é simulado com Req.Test, e os uploads vão para tmp/. O
# cofre do CPF usa um falso que imita as regras do motor, e a limpeza dos
# registros de acesso não roda sozinha.
config :rede_social,
  engine_req_options: [plug: {Req.Test, RedeSocial.Engine}],
  uploads_dir: "tmp/test_uploads",
  vault: RedeSocial.Vault.Fake,
  access_log_janitor: false,
  registro_watcher: false,
  graph_photographer: false,
  govbr_req_options: [plug: {Req.Test, RedeSocial.GovBr}]

config :rede_social, :govbr,
  client_id: "cliente-de-teste",
  client_secret: "segredo-de-teste",
  redirect_uri: "http://localhost:5173/api/govbr/retorno",
  base_url: "https://sso.staging.acesso.gov.br",
  age_fallback: :minor

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :rede_social, RedeSocialWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "NYU04PRrCu8qLyLUx5EiWJj9MPX6Lv0EJRvBzF1zJ194vcAql0V8bDnDuE9hDEFb",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :rede_social, :demo_mode, true
