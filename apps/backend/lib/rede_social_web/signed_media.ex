defmodule RedeSocialWeb.SignedMedia do
  @moduledoc """
  Sem S3, o backend serve /media de uma pasta local. Este plug faz o papel da
  borda: aceita só `/media/s/<prazo>/<assinatura>/<chave>`, confere e passa
  adiante como `/media/<chave>`. Qualquer outro endereço em /media é recusado.
  """
  @behaviour Plug

  import Plug.Conn

  alias RedeSocial.Storage

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["media", "s", expires, signature | rest]} = conn, _opts)
      when rest != [] do
    case Storage.verify(expires, signature, Enum.join(rest, "/")) do
      {:ok, _key} -> %{conn | path_info: ["media" | rest]}
      :error -> forbidden(conn)
    end
  end

  def call(%Plug.Conn{path_info: ["media" | _]} = conn, _opts), do: forbidden(conn)
  def call(conn, _opts), do: conn

  defp forbidden(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(:forbidden, "")
    |> halt()
  end
end
