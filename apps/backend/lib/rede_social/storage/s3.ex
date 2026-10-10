defmodule RedeSocial.Storage.S3 do
  @moduledoc """
  Armazenamento de objetos no padrão S3 (na demo, o Garage). Usa o próprio
  Req, que já assina os pedidos (AWS Signature V4), sem biblioteca da AWS.
  """
  @behaviour RedeSocial.Storage

  @impl true
  def put_file(key, path, content_type) do
    with {:ok, binary} <- File.read(path), do: put_binary(key, binary, content_type)
  end

  @impl true
  def put_binary(key, binary, content_type) do
    case Req.put(request(),
           url: object_url(key),
           body: binary,
           headers: [content_type: content_type]
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, response} -> {:error, {:s3, response.status, response.body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list(prefix), do: list(prefix, nil, [])

  defp list(prefix, token, acc) do
    params =
      [{"list-type", "2"}, {"prefix", prefix}] ++
        if(token, do: [{"continuation-token", token}], else: [])

    case Req.get(request(), url: bucket_url(), params: params, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        keys = for [_, key] <- Regex.scan(~r{<Key>(.*?)</Key>}s, body), do: unescape(key)

        case Regex.run(~r{<NextContinuationToken>(.*?)</NextContinuationToken>}s, body) do
          [_, next] -> list(prefix, unescape(next), acc ++ keys)
          nil -> {:ok, acc ++ keys}
        end

      {:ok, response} ->
        {:error, {:s3, response.status, response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    case Req.delete(request(), url: object_url(key)) do
      {:ok, %{status: status}} when status in [200, 204, 404] -> :ok
      {:ok, response} -> {:error, {:s3, response.status, response.body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request do
    config = Application.fetch_env!(:rede_social, RedeSocial.Storage)

    Req.new(
      aws_sigv4: [
        access_key_id: Keyword.fetch!(config, :access_key_id),
        secret_access_key: Keyword.fetch!(config, :secret_access_key),
        region: Keyword.get(config, :region, "garage"),
        service: :s3
      ],
      retry: :transient
    )
    |> Req.merge(Keyword.get(config, :req_options, []))
  end

  defp bucket_url do
    config = Application.fetch_env!(:rede_social, RedeSocial.Storage)

    String.trim_trailing(Keyword.fetch!(config, :endpoint), "/") <>
      "/" <> Keyword.fetch!(config, :bucket)
  end

  defp object_url(key) do
    segments = key |> String.split("/") |> Enum.map_join("/", &encode_segment/1)
    bucket_url() <> "/" <> segments
  end

  defp encode_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  defp unescape(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end
end
