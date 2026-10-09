defmodule RedeSocial.Repo do
  use Ecto.Repo,
    otp_app: :rede_social,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Onde fazer as leituras pesadas que toleram alguns segundos de atraso
  (candidatos do feed, ligações do grafo, retratos): a réplica de leitura,
  quando existe, ou o próprio banco principal.
  """
  def read do
    if Application.get_env(:rede_social, :read_replica, false),
      do: RedeSocial.Repo.Replica,
      else: __MODULE__
  end
end
