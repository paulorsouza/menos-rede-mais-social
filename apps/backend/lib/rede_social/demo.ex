defmodule RedeSocial.Demo do
  @moduledoc """
  Modo de demonstração: pessoas de exemplo e login gov.br simulado. Fica
  desligado em produção (config :rede_social, :demo_mode).
  """

  @personas ~w(maria.silva joao.pereira bia.santos ana.costa carlos.souza lucas.lima dona.rosa
                theo.alves promo.relampago moderacao.lia moderacao.davi juridico.rui)

  def enabled?, do: Application.get_env(:rede_social, :demo_mode, false)
  def personas, do: @personas
end
