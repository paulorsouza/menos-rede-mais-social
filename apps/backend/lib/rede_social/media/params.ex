defmodule RedeSocial.Media.Params do
  @moduledoc """
  Os parâmetros públicos de vídeo e fotos, lidos de params/video.toml. A
  página de transparência mostra o hash do arquivo que está valendo.
  """

  def get do
    case :persistent_term.get(__MODULE__, nil) do
      nil -> load()
      params -> params
    end
  end

  @doc "Lê o arquivo de novo (depois de mudar o arquivo, sem reiniciar)."
  def load do
    raw = File.read!(path())

    params =
      raw
      |> Toml.decode!()
      |> Map.put("sha256", :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower))

    :persistent_term.put(__MODULE__, params)
    params
  end

  def path do
    Path.join(Application.get_env(:rede_social, :params_dir, "../../params"), "video.toml")
  end

  def ladder, do: get()["hls"]["ladder"]
  def segment_seconds, do: get()["hls"]["segment_seconds"]
  def crf, do: get()["hls"]["crf"]
  def upload, do: get()["upload"]
  def photo, do: get()["photo"]
  def costs, do: get()["costs"]
  def data_saver_short_side, do: get()["data_saver"]["max_short_side"]
  def captions_language, do: get()["captions"]["language"]
end
