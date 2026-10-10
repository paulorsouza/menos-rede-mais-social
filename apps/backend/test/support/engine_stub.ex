defmodule RedeSocial.EngineStub do
  @moduledoc """
  Um motor de mentira para os testes do backend, que responde por caminho.
  As contas aqui são simplificadas de propósito: as de verdade são testadas
  no próprio motor (services/ads-engine) e conferidas de ponta a ponta pelo
  verificador. Aqui interessa o caminho dos dados no backend.
  """

  alias RedeSocial.Engine

  def stub(overrides \\ %{}) do
    Req.Test.stub(Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = if body == "", do: %{}, else: Jason.decode!(body)

      response =
        case Map.fetch(overrides, conn.request_path) do
          {:ok, fun} -> fun.(request)
          :error -> respond(conn.request_path, request)
        end

      Req.Test.json(conn, response)
    end)
  end

  defp respond("/feed/rank", request) do
    %{
      "items" =>
        Enum.map(
          request["candidates"] || [],
          &%{"post_id" => &1["post_id"], "score" => 1, "reasons" => []}
        ),
      "shorts_ad_every" => 6
    }
  end

  defp respond("/transparency", _request) do
    %{
      "shorts_ad_every" => 6,
      "payout_bands" => [%{"up_to" => nil, "percent" => 100}],
      "ads_settings" => %{"payout" => %{"base_cents_per_thousand" => 1100}}
    }
  end

  defp respond("/ads/payout", %{"views" => views}) do
    %{
      "effective_views" => views,
      "payout_cents" => div(views * 1100, 1000),
      "params_version" => 2
    }
  end

  defp respond("/ads/quote", %{"hours_per_day" => hours, "days" => days, "regional" => regional}) do
    per_day = div(hours * 3600, 15)
    price = if regional, do: 1, else: 2

    %{
      "impressions_per_day" => per_day,
      "days" => days,
      "cents_per_impression" => price,
      "total_cents" => per_day * days * price
    }
  end

  # Cada anúncio vai para a candidata da vez, enquanto couber no dia.
  defp respond("/ads/pick", %{"candidates" => candidates, "slots" => slots}) do
    open = Enum.filter(candidates, &(&1["delivered_today"] < &1["daily_budget"]))

    ids =
      if open == [],
        do: [],
        else: Enum.map(0..(slots - 1)//1, &Enum.at(open, rem(&1, length(open)))["id"])

    %{"campaigns" => ids}
  end

  defp respond("/ads/split-shorts", %{"revenue_cents" => revenue, "views" => views}) do
    # Partes iguais por short com anúncio ligado, como em params/ads.toml.
    pool = div(revenue * 55, 100)
    paid = Enum.filter(views, & &1["monetized"])
    total = length(paid)

    cents =
      if total == 0,
        do: %{},
        else:
          paid
          |> Enum.frequencies_by(& &1["creator_id"])
          |> Map.new(fn {id, parts} -> {to_string(id), div(pool * parts, total)} end)

    %{"cents_by_creator" => cents, "fund_cents" => revenue - Enum.sum(Map.values(cents))}
  end

  defp respond("/ads/close-month", %{"creators" => creators}) do
    results =
      Enum.map(creators, fn month ->
        statuses =
          Enum.map(
            month["video_views"],
            &if(&1["viewer_verified"], do: "counted", else: "unverified_viewer")
          )

        counted = Enum.count(statuses, &(&1 == "counted"))
        video_cents = div(counted * 1100, 1000)

        shorts_each =
          Enum.map(
            month["shorts"],
            &if(&1["viewer_verified"], do: div(&1["revenue_cents"] * 55, 100), else: 0)
          )

        total = video_cents + Enum.sum(shorts_each) + month["carry_in_cents"]

        leaves =
          Enum.map(
            month["video_views"],
            &"anuncio-video|#{month["creator"]}|#{&1["viewer"]}|#{&1["at"]}"
          ) ++
            Enum.map(month["shorts"], &"anuncio-shorts|#{month["creator"]}|#{&1["id"]}") ++
            ["total|#{month["month"]}|#{month["creator"]}|#{total}"]

        %{
          "month" => month["month"],
          "creator" => month["creator"],
          "statuses" => statuses,
          "national_views" => counted,
          "regional_views" => 0,
          "discarded_views" => length(statuses) - counted,
          "weighted_views" => counted,
          "effective_views" => counted,
          "video_cents" => video_cents,
          "shorts_cents_each" => shorts_each,
          "shorts_cents" => Enum.sum(shorts_each),
          "carry_in_cents" => month["carry_in_cents"],
          "total_cents" => total,
          "payable" => total >= 100,
          "leaves" => leaves
        }
      end)

    %{"results" => results, "params_sha256" => "abc123", "params_version" => 2}
  end
end
