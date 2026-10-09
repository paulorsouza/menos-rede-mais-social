defmodule RedeSocial.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RedeSocialWeb.Telemetry,
      RedeSocial.Repo,
      {DNSCluster, query: Application.get_env(:rede_social, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RedeSocial.PubSub},
      # Start a worker by calling: RedeSocial.Worker.start_link(arg)
      # {RedeSocial.Worker, arg},
      # Start to serve requests, typically the last entry
      RedeSocialWeb.Endpoint
    ]

    # Apaga os registros de acesso que passaram dos seis meses da lei.
    children =
      if Application.get_env(:rede_social, :access_log_janitor, true),
        do: children ++ [RedeSocial.AccessLogs.Janitor],
        else: children

    # Tira o retrato do grafo e publica a raiz no registro.
    children =
      if Application.get_env(:rede_social, :graph_photographer, true),
        do: children ++ [RedeSocial.GraphCommitments.Photographer],
        else: children

    # Anota no registro público cada versão nova do motor e dos parâmetros.
    children =
      if Application.get_env(:rede_social, :registro_watcher, true),
        do: children ++ [RedeSocial.Registro.Watcher],
        else: children

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RedeSocial.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RedeSocialWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
