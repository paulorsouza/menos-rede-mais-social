defmodule RedeSocial.Engine do
  @moduledoc """
  Cliente do motor de feed e de anúncios (services/engine-server).

  O motor roda separado, em Rust. Se ele cair, o backend continua de pé e
  quem chamou decide o que fazer com o erro.
  """

  def rank(request), do: post("/feed/rank", request)

  @doc "Pagamento por faixas de um total de views, com o valor base de params/ads.toml."
  def payout(views), do: post("/ads/payout", %{views: views})

  def split_shorts(revenue_cents, views) do
    post("/ads/split-shorts", %{revenue_cents: revenue_cents, views: views})
  end

  @doc "Preço de uma campanha, pela tabela pública."
  def quote(hours_per_day, days, regional?) do
    post("/ads/quote", %{hours_per_day: hours_per_day, days: days, regional: regional?})
  end

  @doc "Qual campanha entra em cada um dos próximos anúncios, pelo ritmo do dia."
  def pick(request), do: post("/ads/pick", request)

  @doc "Fecha o mês de cada criador. Pode ser grande: espera mais."
  def close_month(creators) do
    request(
      method: :post,
      url: "/ads/close-month",
      json: %{creators: creators},
      receive_timeout: 120_000
    )
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
