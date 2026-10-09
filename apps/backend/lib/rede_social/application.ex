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

    # Réplica de leitura, quando configurada (config/runtime.exs).
    children =
      if Application.get_env(:rede_social, :read_replica, false),
        do: List.insert_at(children, 2, RedeSocial.Repo.Replica),
        else: children

    # Trabalhos de fundo: apagar acessos vencidos, retratar o grafo e anotar
    # cada versão do motor no registro. Só rodam junto com o servidor de
    # verdade, nunca em tarefas avulsas como seeds e migrações, para não
    # retratar um grafo pela metade.
    background =
      for {flag, worker} <- [
            access_log_janitor: RedeSocial.AccessLogs.Janitor,
            graph_photographer: RedeSocial.GraphCommitments.Photographer,
            registro_watcher: RedeSocial.Registro.Watcher
          ],
          Application.get_env(:rede_social, flag, true),
          do: worker

    children =
      if Phoenix.Endpoint.server?(:rede_social, RedeSocialWeb.Endpoint),
        do: children ++ background,
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
