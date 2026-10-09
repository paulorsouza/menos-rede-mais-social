defmodule RedeSocial.Media do
  @moduledoc """
  Guarda as fotos e os vídeos enviados. Nesta fase os arquivos ficam no disco
  do servidor e são servidos em /uploads. A transcodificação em Rust entra na
  Fase 3 do plano.
  """

  @extensions %{
    photo: ~w(.jpg .jpeg .png .webp .gif),
    video: ~w(.mp4 .webm .mov),
    short: ~w(.mp4 .webm .mov)
  }

  def store(%Plug.Upload{filename: filename, path: path}, kind) do
    extension = filename |> Path.extname() |> String.downcase()

    if extension in Map.get(@extensions, kind, []) do
      name = random_name(extension)
      File.mkdir_p!(dir())
      File.cp!(path, Path.join(dir(), name))
      {:ok, "/uploads/" <> name}
    else
      {:error, :unsupported_file}
    end
  end

  def store(_upload, _kind), do: {:ok, nil}

  @doc "Grava um arquivo gerado pelo próprio sistema, como os dados de demonstração."
  def store_binary(binary, extension) do
    name = random_name(extension)
    File.mkdir_p!(dir())
    File.write!(Path.join(dir(), name), binary)
    "/uploads/" <> name
  end

  @doc "Caminho no disco para um arquivo novo, para quem gera o arquivo por fora (ffmpeg)."
  def new_file(extension) do
    name = random_name(extension)
    File.mkdir_p!(dir())
    {Path.join(dir(), name), "/uploads/" <> name}
  end

  @doc "Apaga um arquivo enviado. Só aceita caminhos de /uploads, sem subir de pasta."
  def delete("/uploads/" <> name) do
    if name == Path.basename(name), do: File.rm(Path.join(dir(), name))
    :ok
  end

  def delete(_path), do: :ok

  def dir, do: Application.get_env(:rede_social, :uploads_dir, "priv/uploads")

  defp random_name(extension) do
    Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false) <> extension
  end
end
