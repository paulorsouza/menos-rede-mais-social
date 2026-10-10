defmodule RedeSocial.Media.Captions do
  @moduledoc """
  Legendas automáticas, para quem não ouve e para quem assiste sem som.

  O áudio é transcrito pelo whisper.cpp, rodando como serviço da própria
  rede (WHISPER_URL). Nenhum áudio sai para empresa de fora. Sem o serviço
  configurado, os vídeos ficam sem legenda e nada mais muda.
  """

  alias RedeSocial.Media.{FFmpeg, Params}

  def enabled?, do: url() != nil

  @doc "Transcreve o áudio de um vídeo e devolve a legenda em WebVTT."
  def generate(source, out_dir) do
    wav = Path.join(out_dir, "audio.wav")

    with {:ok, _} <- FFmpeg.audio(source, wav),
         {:ok, %{status: 200, body: "WEBVTT" <> _ = vtt}} <-
           Req.post(
             Req.new(Application.get_env(:rede_social, :whisper_req_options, [])),
             url: url() <> "/inference",
             form_multipart: [
               file: {File.read!(wav), filename: "audio.wav", content_type: "audio/wav"},
               response_format: "vtt",
               language: Params.captions_language(),
               temperature: "0.0"
             ],
             receive_timeout: :timer.minutes(30),
             retry: false
           ) do
      {:ok, vtt}
    else
      {:ok, %{status: status}} -> {:error, {:whisper, status}}
      # Serviço desligado (a demo sem o perfil "legendas", por exemplo).
      {:error, %Req.TransportError{}} -> {:error, :unavailable}
      error -> error
    end
  end

  defp url, do: Application.get_env(:rede_social, :whisper_url)
end
