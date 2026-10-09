defmodule RedeSocial.Repo.Replica do
  @moduledoc """
  Réplica de leitura do PostgreSQL. Só existe quando DATABASE_REPLICA_URL
  está configurada; sem ela, `RedeSocial.Repo.read/0` devolve o banco
  principal.
  """
  use Ecto.Repo,
    otp_app: :rede_social,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
