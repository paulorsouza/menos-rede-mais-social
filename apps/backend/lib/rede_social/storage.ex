defmodule RedeSocial.Storage do
  @moduledoc """
  Onde ficam as fotos e os vídeos já processados.

  Na demonstração com Docker, é o Garage, um armazenamento de objetos no
  padrão S3, com a borda (infra/borda) na frente fazendo o papel da CDN. Sem
  S3 configurado, os arquivos ficam numa pasta local servida pelo próprio
  backend em /media, o que basta para desenvolver e para os testes.

  Tudo o que é guardado aqui é público para quem tem o endereço. Os nomes
  levam um id aleatório, então ninguém chega num arquivo sem antes receber o
  endereço da rede.

  Uma chave é o caminho dentro do armazenamento, como `v/<id>/master.m3u8`.
  O endereço público é `/media/` mais a chave.
  """

  @callback put_file(key :: String.t(), path :: Path.t(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback put_binary(key :: String.t(), binary(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback list(prefix :: String.t()) :: {:ok, [String.t()]} | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}

  @prefix "/media/"

  def put_file(key, path, content_type \\ nil),
    do: adapter().put_file(key, path, content_type || content_type(key))

  def put_binary(key, binary, content_type \\ nil),
    do: adapter().put_binary(key, binary, content_type || content_type(key))

  @doc "Sobe uma pasta inteira, mantendo os caminhos. Devolve o total de bytes."
  def put_dir(prefix, dir) do
    files = Path.wildcard(Path.join(dir, "**/*")) |> Enum.filter(&File.regular?/1)

    Enum.reduce_while(files, {:ok, 0}, fn file, {:ok, total} ->
      key = prefix <> "/" <> Path.relative_to(file, dir)

      case put_file(key, file) do
        :ok -> {:cont, {:ok, total + File.stat!(file).size}}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Apaga tudo o que começa com o prefixo."
  def delete_prefix(prefix) do
    with {:ok, keys} <- adapter().list(prefix) do
      Enum.each(keys, &adapter().delete/1)
    end
  end

  @doc "O endereço público de uma chave."
  def path(key), do: @prefix <> key

  @doc "A chave de um endereço público, ou nil se não for daqui."
  def key(@prefix <> key), do: key
  def key(_path), do: nil

  @doc """
  O endereço que vai para o app. Com MEDIA_BASE_URL (uma CDN em outro
  domínio), troca o /media do começo por ela.
  """
  def url(nil), do: nil

  def url(@prefix <> key = path) do
    case Application.get_env(:rede_social, :media_base_url) do
      nil -> path
      base -> String.trim_trailing(base, "/") <> "/" <> key
    end
  end

  def url(path), do: path

  def content_type(key) do
    case Path.extname(key) do
      ".m3u8" -> "application/vnd.apple.mpegurl"
      ".m4s" -> "video/iso.segment"
      ".mp4" -> "video/mp4"
      ".vtt" -> "text/vtt; charset=utf-8"
      ".webp" -> "image/webp"
      ".jpg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".svg" -> "image/svg+xml"
      _ -> "application/octet-stream"
    end
  end

  defp adapter do
    Application.get_env(:rede_social, __MODULE__, [])
    |> Keyword.get(:adapter, RedeSocial.Storage.Local)
  end
end
