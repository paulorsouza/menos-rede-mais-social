defmodule RedeSocial.Media.Costs do
  @moduledoc """
  Quanto custa uma hora de vídeo, que é o portão da Fase 3 do plano.

  São duas contas lado a lado:

    * medido: o que os vídeos já convertidos realmente ocuparam e gastaram
      de CPU, dividido pelas horas de vídeo;
    * teto: o máximo que os parâmetros permitem, pelo bitrate de cada degrau
      em params/video.toml. Vídeo simples sai bem abaixo do teto; vídeo com
      muito movimento chega perto dele.

  Os preços são os de [costs] em params/video.toml, ilustrativos até alguém
  operar a rede de verdade.
  """

  import Ecto.Query

  alias RedeSocial.Media.{Asset, Params}
  alias RedeSocial.Repo

  @gb 1_000_000_000
  @hour_ms 3_600_000

  def summary do
    prices = Params.costs()
    ladder = Params.ladder()

    %{
      prices: prices,
      measured: measured(prices),
      ceiling: ceiling(ladder, prices)
    }
  end

  defp measured(prices) do
    assets =
      Repo.all(
        from a in Asset,
          where: a.status == :ready and a.duration_ms > 0,
          select: map(a, [:duration_ms, :stored_bytes, :cpu_ms, :renditions])
      )

    hours = Enum.sum_by(assets, & &1.duration_ms) / @hour_ms

    if hours == 0 do
      %{videos: 0, hours: 0}
    else
      storage_gb = Enum.sum_by(assets, &(&1.stored_bytes || 0)) / @gb / hours
      cpu_hours = Enum.sum_by(assets, &(&1.cpu_ms || 0)) / @hour_ms / hours

      %{
        videos: length(assets),
        hours: Float.round(hours, 4),
        storage_gb_per_hour: Float.round(storage_gb, 4),
        cpu_hours_per_hour: Float.round(cpu_hours, 3),
        store_cents: store_cents(storage_gb, prices),
        transcode_cents: Float.round(cpu_hours * prices["cpu_cents_per_hour"], 2),
        watch: watch_measured(assets, prices)
      }
    end
  end

  # Bytes de cada degrau por hora assistida nele: só conta os vídeos que têm
  # aquele degrau.
  defp watch_measured(assets, prices) do
    assets
    |> Enum.flat_map(fn asset ->
      Enum.map(asset.renditions || [], &{&1["short_side"], &1["bytes"], asset.duration_ms})
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {side, rows} ->
      gb_per_hour =
        Enum.sum_by(rows, &elem(&1, 1)) / @gb / (Enum.sum_by(rows, &elem(&1, 2)) / @hour_ms)

      watch_row(side, gb_per_hour, prices)
    end)
  end

  defp ceiling(ladder, prices) do
    watch =
      Enum.map(ladder, fn step ->
        watch_row(
          step["short_side"],
          gb_per_hour(step["video_kbps"] + step["audio_kbps"]),
          prices
        )
      end)

    # Um vídeo enviado em 1080 guarda todos os degraus.
    storage_gb = Enum.sum_by(watch, & &1.gb_per_hour)

    %{
      storage_gb_per_hour: Float.round(storage_gb, 4),
      store_cents: store_cents(storage_gb, prices),
      watch: watch
    }
  end

  defp watch_row(side, gb_per_hour, prices) do
    %{
      short_side: side,
      gb_per_hour: Float.round(gb_per_hour, 4),
      cents: Float.round(gb_per_hour * prices["egress_cents_per_gb"], 2)
    }
  end

  defp store_cents(gb_per_hour, prices) do
    Float.round(gb_per_hour * prices["storage_cents_per_gb_month"] * prices["months_stored"], 2)
  end

  defp gb_per_hour(kbps), do: kbps * 1000 / 8 * 3600 / @gb

  @doc "O arquivo de parâmetros, no mesmo formato que o motor publica os dele."
  def params_file do
    params = Params.get()

    %{
      path: "params/video.toml",
      version: params["version"],
      sha256: params["sha256"],
      source: File.read!(Params.path())
    }
  end
end
