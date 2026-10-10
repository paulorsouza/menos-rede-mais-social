defmodule RedeSocial.Media do
  @moduledoc """
  Fotos e vídeos dos posts.

  Foto é limpa (sem os metadados da câmera, que podem ter a localização) e
  guardada na hora. Vídeo entra na fila: o post nasce "processando", o
  vídeo vira HLS com vários degraus de qualidade e o post aparece para os
  outros quando termina. Quem decide se é foto, vídeo ou short é o próprio
  arquivo, nunca uma escolha de quem publica.

  Os parâmetros (degraus, tamanhos, limites) estão em params/video.toml.
  """

  import Ecto.Query

  require Logger

  alias RedeSocial.{Repo, Storage, Uploads}
  alias RedeSocial.Media.{Asset, Captions, FFmpeg, Params}
  alias RedeSocial.Social.Post

  @doc """
  Prepara a mídia de um post novo. A origem é um envio (`{:upload, id}`),
  um arquivo de formulário (`%Plug.Upload{}`) ou nada.

  Devolve os campos do post. Para vídeo, devolve também o `asset` ainda não
  gravado, que o post grava junto com ele e manda para a fila.
  """
  def prepare(_account, nil), do: {:ok, nil}

  def prepare(account, source) do
    staging = Path.join(Uploads.staging_dir(), "fonte-" <> Ecto.UUID.generate())

    with {:ok, file} <- take(account, source, staging),
         {:ok, probe} <- FFmpeg.probe(file.path),
         :ok <- check_duration(probe) do
      case probe.type do
        :photo -> store_photo(staging, probe)
        :video -> {:ok, video_fields(account, staging, probe)}
      end
    else
      error ->
        File.rm(staging)
        error
    end
  end

  defp take(account, {:upload, id}, staging), do: Uploads.take(account, id, staging)

  defp take(_account, %Plug.Upload{path: path, filename: filename}, staging) do
    File.mkdir_p!(Path.dirname(staging))
    File.cp!(path, staging)
    {:ok, %{path: staging, filename: filename}}
  end

  defp take(_account, _other, _staging), do: {:error, :unsupported_file}

  defp check_duration(%{duration_ms: ms}) when is_integer(ms) do
    if ms > Params.upload()["max_video_minutes"] * 60_000, do: {:error, :too_long}, else: :ok
  end

  defp check_duration(_probe), do: :ok

  @doc """
  Short é vídeo em pé de até `short_max_seconds`. Vídeo gravado no navegador
  às vezes chega sem duração; aí vale só a orientação.
  """
  def kind_for(%{type: :photo}), do: :photo

  def kind_for(%{width: width, height: height, duration_ms: ms}) do
    short? = is_nil(ms) or ms <= Params.upload()["short_max_seconds"] * 1000
    if height > width and short?, do: :short, else: :video
  end

  defp store_photo(source, probe) do
    out_dir = work_dir()

    try do
      with {:ok, file} <- FFmpeg.photo(source, probe, out_dir),
           key = "f/" <> Ecto.UUID.generate() <> Path.extname(file),
           :ok <- Storage.put_file(key, file) do
        {:ok,
         %{
           kind: :photo,
           media_status: :ready,
           media_path: Storage.path(key),
           width: probe.width,
           height: probe.height
         }}
      end
    after
      File.rm(source)
      File.rm_rf(out_dir)
    end
  end

  defp video_fields(account, source, probe) do
    asset = %Asset{
      id: Ecto.UUID.generate(),
      account_id: account && account.id,
      kind: :video,
      status: :processing,
      source_path: source,
      source_bytes: File.stat!(source).size,
      width: probe.width,
      height: probe.height,
      duration_ms: probe.duration_ms,
      has_audio: probe.has_audio
    }

    %{
      kind: kind_for(probe),
      media_status: :processing,
      width: probe.width,
      height: probe.height,
      duration_ms: probe.duration_ms,
      asset: asset
    }
  end

  @doc """
  Converte o vídeo de um asset em HLS, guarda tudo no armazenamento e libera
  os posts que esperavam por ele. Depois tenta gerar as legendas. Roda na
  fila (Media.TranscodeWorker) ou direto, nos dados da demonstração.
  """
  def process(%Asset{} = asset) do
    out_dir = work_dir()
    probe = Map.take(asset, [:width, :height, :duration_ms, :has_audio])

    try do
      with true <- (asset.source_path && File.exists?(asset.source_path)) || {:error, :no_source},
           {:ok, result} <- FFmpeg.hls(asset.source_path, probe, out_dir),
           {:ok, _poster} <- FFmpeg.poster(asset.source_path, probe, out_dir),
           {:ok, stored} <- Storage.put_dir(Asset.prefix(asset), out_dir) do
        asset = ready(asset, result, stored, asset.duration_ms || playlist_ms(out_dir))
        asset = maybe_captions(asset, out_dir)
        # O original não fica guardado: guardar custa, e os degraus bastam.
        File.rm(asset.source_path)
        {:ok, asset |> Ecto.Changeset.change(source_path: nil) |> Repo.update!()}
      end
    after
      File.rm_rf(out_dir)
    end
  end

  defp ready(asset, result, stored, duration_ms) do
    prefix = Asset.prefix(asset)

    renditions =
      Enum.map(result.renditions, fn step ->
        Map.new(step, fn {key, value} -> {to_string(key), value} end)
      end)

    {:ok, asset} =
      Repo.transaction(fn ->
        asset =
          asset
          |> Ecto.Changeset.change(
            status: :ready,
            renditions: renditions,
            stored_bytes: stored,
            cpu_ms: result.cpu_ms,
            wall_ms: result.wall_ms,
            duration_ms: duration_ms,
            error: nil
          )
          |> Repo.update!()

        Repo.update_all(
          from(p in Post, where: p.media_asset_id == ^asset.id),
          set: [
            media_status: :ready,
            media_path: Storage.path(prefix <> "/master.m3u8"),
            poster_path: Storage.path(prefix <> "/capa.webp"),
            duration_ms: duration_ms
          ]
        )

        asset
      end)

    asset
  end

  defp maybe_captions(%Asset{has_audio: true} = asset, out_dir) do
    with true <- Captions.enabled?(),
         {:ok, vtt} <- Captions.generate(asset.source_path, out_dir),
         key = Asset.prefix(asset) <> "/legendas.vtt",
         :ok <- Storage.put_binary(key, vtt) do
      Repo.update_all(from(p in Post, where: p.media_asset_id == ^asset.id),
        set: [captions_path: Storage.path(key)]
      )

      asset |> Ecto.Changeset.change(captions: true) |> Repo.update!()
    else
      false ->
        asset

      {:error, :unavailable} ->
        Logger.info("serviço de legendas fora do ar: o vídeo #{asset.id} fica sem legenda")
        asset

      error ->
        # Legenda é ajuda, não condição: o vídeo fica no ar sem ela.
        Logger.warning("legendas do vídeo #{asset.id} não saíram: #{inspect(error)}")
        asset
    end
  end

  defp maybe_captions(asset, _out_dir), do: asset

  @doc "Desiste do vídeo: o post fica marcado como falha e o original é apagado."
  def fail(%Asset{} = asset, reason) do
    if asset.source_path, do: File.rm(asset.source_path)

    Repo.transaction(fn ->
      asset
      |> Ecto.Changeset.change(status: :failed, error: inspect(reason), source_path: nil)
      |> Repo.update!()

      Repo.update_all(from(p in Post, where: p.media_asset_id == ^asset.id),
        set: [media_status: :failed]
      )
    end)
  end

  # Duração somada dos pedaços, para vídeo que chegou sem duração.
  defp playlist_ms(out_dir) do
    out_dir
    |> Path.join("*/index.m3u8")
    |> Path.wildcard()
    |> List.first()
    |> File.read!()
    |> then(&Regex.scan(~r/#EXTINF:([\d.]+)/, &1))
    |> Enum.map(fn [_, seconds] -> seconds |> Float.parse() |> elem(0) end)
    |> Enum.sum()
    |> Kernel.*(1000)
    |> round()
  end

  @doc """
  Processa um arquivo de vídeo na hora, sem fila, e devolve os campos do
  post. Para os dados da demonstração e para as gravações de live.
  """
  def ingest_now(account_id, path) do
    with {:ok, probe} <- FFmpeg.probe(path),
         %{asset: asset} = fields <- video_fields(%{id: account_id}, path, probe),
         {:ok, asset} <- asset |> Repo.insert!() |> process() do
      {:ok,
       fields
       |> Map.delete(:asset)
       |> Map.merge(%{
         media_asset_id: asset.id,
         media_status: :ready,
         media_path: Storage.path(Asset.prefix(asset) <> "/master.m3u8"),
         poster_path: Storage.path(Asset.prefix(asset) <> "/capa.webp"),
         duration_ms: asset.duration_ms,
         captions_path:
           if(asset.captions, do: Storage.path(Asset.prefix(asset) <> "/legendas.vtt"))
       })}
    end
  end

  @doc "Grava um arquivo gerado pelo próprio sistema, como as artes da demonstração."
  def store_binary(binary, extension) do
    key = "f/" <> Ecto.UUID.generate() <> extension
    :ok = Storage.put_binary(key, binary)
    Storage.path(key)
  end

  @doc "Apaga do armazenamento a mídia de um post: a foto, ou todos os arquivos do vídeo."
  def delete(%{media_asset_id: asset_id}) when is_binary(asset_id) do
    case Repo.get(Asset, asset_id) do
      %Asset{source_path: source} when is_binary(source) -> File.rm(source)
      _ -> :ok
    end

    Storage.delete_prefix("v/" <> asset_id <> "/")
  end

  def delete(%{media_path: path}) do
    case Storage.key(path) do
      "f/" <> _ = key -> Storage.delete_prefix(key)
      _ -> :ok
    end
  end

  defp work_dir do
    dir = Path.join(System.tmp_dir!(), "rede-social-" <> Ecto.UUID.generate())
    File.mkdir_p!(dir)
    dir
  end
end
