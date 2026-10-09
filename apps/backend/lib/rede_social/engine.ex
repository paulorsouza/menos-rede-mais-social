defmodule RedeSocial.Engine do
  @moduledoc """
  Cliente do motor de feed e de anúncios (services/engine-server).

  O motor roda separado, em Rust. Se ele cair, o backend continua de pé e
  quem chamou decide o que fazer com o erro.
  """

  def rank(request), do: post("/feed/rank", request)

  def payout(views, cents_per_thousand) do
    post("/ads/payout", %{views: views, cents_per_thousand: cents_per_thousand})
  end

  def split_shorts(revenue_cents, views) do
    post("/ads/split-shorts", %{revenue_cents: revenue_cents, views: views})
  end

  def transparency, do: get("/transparency")

  def vault_seal(plaintext, context),
    do: post("/vault/seal", %{plaintext: plaintext, context: context})

  def vault_verify(sealed, partial),
    do: post("/vault/verify", %{sealed: sealed, partial: partial})

  def vault_open(sealed, context, partials) do
    post("/vault/open", %{sealed: sealed, context: context, partials: partials})
  end

  def vault_demo_partial(index, sealed),
    do: post("/vault/demo-partial", %{index: index, sealed: sealed})

  defp get(path), do: request(method: :get, url: path)
  defp post(path, body), do: request(method: :post, url: path, json: body)

  defp request(options) do
    case Req.request(client(), options) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:status, status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp client do
    Req.new(
      base_url: Application.get_env(:rede_social, :engine_url),
      retry: false,
      receive_timeout: 5_000
    )
    |> Req.merge(Application.get_env(:rede_social, :engine_req_options, []))
  end
end
