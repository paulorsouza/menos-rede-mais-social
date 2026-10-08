defmodule RedeSocial.Repo do
  use Ecto.Repo,
    otp_app: :rede_social,
    adapter: Ecto.Adapters.Postgres
end
