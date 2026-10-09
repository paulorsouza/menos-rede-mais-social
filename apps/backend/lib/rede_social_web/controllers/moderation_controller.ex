defmodule RedeSocialWeb.ModerationController do
  @moduledoc """
  Regras de conteúdo (públicas) e a mesa da moderação: fila de denúncias,
  remoção citando a regra, manter o post e julgar recursos.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.{Moderation, Social}
  alias RedeSocial.Moderation.Rules
  alias RedeSocialWeb.Present

  action_fallback RedeSocialWeb.FallbackController

  def rules(conn, _params), do: json(conn, %{rules: Rules.all()})

  def queue(conn, _params) do
    json(conn, %{
      reports: Enum.map(Moderation.queue(), &Present.queue_entry/1),
      appeals: Enum.map(Moderation.pending_appeals(), &Present.appeal/1)
    })
  end

  def remove(conn, %{"id" => id} = params) do
    with %{} = post <- find(id),
         {:ok, _post} <- Moderation.remove(conn.assigns.current_account, post, rule(params)) do
      json(conn, %{ok: true})
    end
  end

  def keep(conn, %{"id" => id}) do
    with %{} = post <- find(id),
         {:ok, _action} <- Moderation.keep(conn.assigns.current_account, post) do
      json(conn, %{ok: true})
    end
  end

  def decide(conn, %{"id" => id} = params) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %{} = appeal <- Moderation.get_appeal(id),
         {:ok, _appeal} <-
           Moderation.decide(conn.assigns.current_account, appeal, params["outcome"]) do
      json(conn, %{ok: true})
    else
      :error -> {:error, :not_found}
      other -> other
    end
  end

  defp find(id) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> Social.get_post_any(id)
      _ -> nil
    end
  end

  defp rule(%{"rule" => rule}) when is_integer(rule), do: rule

  defp rule(%{"rule" => rule}) when is_binary(rule) do
    case Integer.parse(rule) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp rule(_params), do: nil
end
