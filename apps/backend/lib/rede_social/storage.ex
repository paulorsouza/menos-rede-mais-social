defmodule RedeSocial.Storage do
  @moduledoc """
  Onde ficam as fotos e os vídeos já processados.

  Na demonstração com Docker, é o Garage, um armazenamento de objetos no
  padrão S3, com a borda (infra/borda) na frente fazendo o papel da CDN. Sem
  S3 configurado, os arquivos ficam numa pasta local servida pelo próprio
  backend em /media, o que basta para desenvolver e para os testes.

  Os nomes levam um id aleatório, e o endereço que vai para o app é assinado
  e tem prazo: `/media/s/<prazo>/<assinatura>/<chave>`. A borda (ou, sem S3,
  o próprio backend) confere a assinatura e recusa endereço vencido ou sem
  assinatura. Assim um link que vazou para de abrir, inclusive o de foto ou
  vídeo de menor, e o de um post apagado.

  A assinatura cobre o prazo e o escopo da chave (os dois primeiros pedaços,
  como `v/<id>` ou `f/<id>.webp`), e não o arquivo exato: os pedaços de um
  vídeo HLS são pedidos por endereço relativo e herdam a assinatura do
  caminho. É o formato do `secure_link` do nginx.

  Uma chave é o caminho dentro do armazenamento, como `v/<id>/master.m3u8`.
  O caminho guardado no banco é `/media/` mais a chave, sem assinatura.
  """

  @callback put_file(key :: String.t(), path :: Path.t(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback put_binary(key :: String.t(), binary(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback list(prefix :: String.t()) :: {:ok, [String.t()]} | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
  @callback get(key :: String.t()) :: {:ok, binary()} | {:error, term()}

  @prefix "/media/"
  # O link vale de 6 a 7 horas: o prazo fecha na hora cheia, para o mesmo
  # arquivo ter o mesmo endereço por uma hora e a borda aproveitar a cópia.
  @link_hours 6

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

  def get(key), do: adapter().get(key)
  def delete(key), do: adapter().delete(key)

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
  def url(path, now \\ DateTime.utc_now())
  def url(nil, _now), do: nil

  def url(@prefix <> key, now) do
    signed = signed_key(key, now)

    case Application.get_env(:rede_social, :media_base_url) do
      nil -> @prefix <> signed
      base -> String.trim_trailing(base, "/") <> "/" <> signed
    end
  end

  def url(path, _now), do: path

  defp signed_key(key, now) do
    expires = (div(DateTime.to_unix(now), 3600) + 1 + @link_hours) * 3600
    "s/#{expires}/#{signature(expires, key)}/#{key}"
  end

  @doc """
  Confere um endereço assinado (o que vem depois de `/media/s/`) e devolve a
  chave, ou erro se a assinatura não bate ou o prazo passou.
  """
  def verify(expires, signature, key, now \\ DateTime.utc_now()) do
    with {expires, ""} <- Integer.parse(expires),
         true <- expires > DateTime.to_unix(now),
         true <- Plug.Crypto.secure_compare(signature, signature(expires, key)) do
      {:ok, key}
    else
      _ -> :error
    end
  end

  # md5(prazo + escopo + " " + segredo), em base64 de URL, como o nginx confere.
  defp signature(expires, key) do
    scope = key |> String.split("/") |> Enum.take(2) |> Enum.join("/")
    secret = Application.fetch_env!(:rede_social, :media_link_secret)

    :crypto.hash(:md5, "#{expires}#{scope} #{secret}")
    |> Base.url_encode64(padding: false)
  end

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
