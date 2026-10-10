defmodule RedeSocial.Uploads do
  @moduledoc """
  Envio que retoma de onde parou, no protocolo tus 1.0 (tus.io). O app manda
  o arquivo em pedaços; se a conexão cair, pergunta quantos bytes chegaram e
  continua dali, em vez de começar de novo. Numa internet fraca, é a
  diferença entre o vídeo chegar ou não.

  O envio começa assim que a pessoa escolhe o arquivo, enquanto ela ainda
  escreve a legenda. Quando ela publica, o post leva o id do envio.

  Os bytes ficam na pasta de trabalho do servidor que recebeu o envio, e é o
  mesmo servidor que converte o vídeo depois. Envio que não vira post em um
  dia é apagado.
  """

  import Ecto.Query

  alias RedeSocial.{Accounts, Repo}
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Media.Params
  alias RedeSocial.Uploads.Upload

  @accepted ~w(image/jpeg image/png image/webp image/gif video/mp4 video/webm video/quicktime)
  @max_age_hours 24

  @doc "Abre um envio de `length` bytes."
  def create(%Account{} = account, length, metadata) do
    content_type = metadata["filetype"]

    cond do
      not Accounts.verified?(account) -> {:error, :not_verified}
      not is_integer(length) or length <= 0 -> {:error, :invalid_length}
      content_type not in @accepted -> {:error, :unsupported_file}
      length > max_bytes(content_type) -> {:error, :too_large}
      true -> insert(account, length, metadata)
    end
  end

  defp insert(account, length, metadata) do
    upload =
      Repo.insert!(%Upload{
        account_id: account.id,
        length: length,
        filename: metadata["filename"] |> to_string() |> String.slice(0, 200),
        content_type: metadata["filetype"]
      })

    File.mkdir_p!(staging_dir())
    File.write!(path(upload), "")
    {:ok, upload}
  end

  @doc "O tamanho máximo de um envio deste tipo, em bytes."
  def max_bytes("image/" <> _), do: Params.upload()["max_photo_mb"] * 1_000_000
  def max_bytes(_content_type), do: Params.upload()["max_video_mb"] * 1_000_000

  def max_bytes, do: Params.upload()["max_video_mb"] * 1_000_000

  def get(%Account{id: account_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Upload{used_at: nil} = upload <- Repo.get_by(Upload, id: id, account_id: account_id) do
      upload
    else
      _ -> nil
    end
  end

  @doc "Quantos bytes já chegaram. O arquivo em disco é a fonte da verdade."
  def offset(%Upload{} = upload) do
    case File.stat(path(upload)) do
      {:ok, %{size: size}} -> size
      {:error, _} -> 0
    end
  end

  @doc """
  Acrescenta bytes no fim do arquivo. `read` recebe um estado (no
  controlador, a conexão) e devolve `{:data, bytes, estado}`, `{:last,
  bytes, estado}`, `{:done, estado}` ou `{:error, motivo, estado}`. Cada
  pedaço é gravado na hora: se a conexão cair no meio, o que chegou fica
  guardado. Dois pedidos ao mesmo tempo para o mesmo envio não passam
  (`:locked`). Devolve `{resultado, estado}`.
  """
  def append(%Upload{} = upload, state, read) do
    lock = {{:upload, upload.id}, self()}

    if :global.set_lock(lock, [node()], 0) do
      try do
        {:ok, file} = File.open(path(upload), [:append, :binary])

        try do
          write_all(file, upload, state, read)
        after
          File.close(file)
        end
      after
        :global.del_lock(lock, [node()])
      end
    else
      {{:error, :locked}, state}
    end
  end

  defp write_all(file, upload, state, read) do
    case read.(state) do
      {:done, state} ->
        {:ok, state}

      {:error, reason, state} ->
        {{:error, reason}, state}

      {tag, data, state} when tag in [:data, :last] ->
        if offset(upload) + byte_size(data) > upload.length do
          {{:error, :too_large}, state}
        else
          IO.binwrite(file, data)
          if tag == :last, do: {:ok, state}, else: write_all(file, upload, state, read)
        end
    end
  end

  @doc "Marca como completo quando todos os bytes chegaram."
  def finish(%Upload{} = upload) do
    if offset(upload) == upload.length and is_nil(upload.completed_at) do
      upload
      |> Ecto.Changeset.change(completed_at: now())
      |> Repo.update!()
    else
      upload
    end
  end

  @doc """
  Entrega o arquivo para virar post. Só envio completo, da própria conta e
  ainda não usado. O arquivo sai da pasta de envios: daqui em diante é de
  quem vai processar.
  """
  def take(%Account{} = account, id, target) do
    case get(account, id) do
      nil ->
        {:error, :upload_not_found}

      %Upload{completed_at: nil} ->
        {:error, :upload_incomplete}

      upload ->
        File.mkdir_p!(Path.dirname(target))
        File.rename!(path(upload), target)
        upload |> Ecto.Changeset.change(used_at: now()) |> Repo.update!()
        {:ok, %{path: target, filename: upload.filename, content_type: upload.content_type}}
    end
  end

  @doc "Desiste do envio (extensão termination do tus)."
  def delete(%Upload{} = upload) do
    File.rm(path(upload))
    Repo.delete(upload)
  end

  @doc "Apaga envios abandonados há mais de um dia."
  def purge_stale(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@max_age_hours * 3600, :second)

    stale =
      Repo.all(from u in Upload, where: u.inserted_at < ^cutoff and is_nil(u.used_at))

    Enum.each(stale, &delete/1)
    Repo.delete_all(from u in Upload, where: u.inserted_at < ^cutoff)
    length(stale)
  end

  def path(%Upload{id: id}), do: Path.join(staging_dir(), "envio-" <> id)

  def staging_dir, do: Application.get_env(:rede_social, :staging_dir, "priv/staging")

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
