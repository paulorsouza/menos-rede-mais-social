defmodule RedeSocialWeb.LiveController do
  use RedeSocialWeb, :controller

  alias RedeSocial.Lives
  alias RedeSocial.Lives.Live

  action_fallback RedeSocialWeb.FallbackController

  @doc """
  Abre uma live e devolve os dois jeitos de transmitir: pelo navegador
  (WHIP) e pelo OBS (RTMP). A chave só aparece nesta resposta.

  O endereço do RTMP vem da configuração (AO_VIVO_RTMP_URL); sem ela, o app
  usa o endereço em que ele mesmo está aberto.
  """
  def create(conn, params) do
    with {:ok, live, key} <- Lives.create(conn.assigns.current_account, params) do
      path = Live.path(live)

      conn
      |> put_status(:created)
      |> json(%{
        live: %{
          id: live.id,
          post_id: live.post_id,
          key: key,
          whip_url: "/whip/#{path}/whip",
          rtmp: %{
            server: Application.get_env(:rede_social, :ao_vivo, [])[:rtmp_url],
            stream_key: "#{live.id}?chave=#{key}"
          }
        }
      })
    end
  end

  @doc """
  Chamado pelo servidor de transmissão a cada conexão. Responde 200 para
  deixar e 401 para recusar. O segredo na URL garante que quem pergunta é o
  servidor de transmissão (infra/ao-vivo/mediamtx.yml).
  """
  def authorize(conn, params) do
    secret = Application.get_env(:rede_social, :ao_vivo, [])[:secret]

    if is_binary(secret) and Plug.Crypto.secure_compare(params["segredo"] || "", secret) and
         Lives.authorize(params) == :ok do
      send_resp(conn, :ok, "")
    else
      send_resp(conn, :unauthorized, "")
    end
  end
end
