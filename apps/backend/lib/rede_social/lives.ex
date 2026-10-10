defmodule RedeSocial.Lives do
  @moduledoc """
  Lives. Quem transmite abre a live e recebe uma chave; o servidor de
  transmissão (MediaMTX, em infra/ao-vivo) pergunta ao backend, a cada
  conexão, se aquela chave pode transmitir naquele caminho.

  O post da live só aparece para os outros quando a transmissão começa de
  verdade. Quando ela acaba, a gravação passa pelo mesmo caminho de qualquer
  vídeo enviado e o post vira vídeo ou short.

  Menor de idade não faz live: o perfil dele é privado, e uma transmissão
  aberta não combina com isso.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias RedeSocial.{Accounts, Repo}
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Lives.{Live, RecordingWorker}
  alias RedeSocial.Social.Post

  # Live aberta que não começou em uma hora é desfeita.
  @waiting_limit_seconds 3600

  @doc "Abre uma live. Devolve a live e a chave de transmissão, que só aparece aqui."
  def create(%Account{} = account, attrs) do
    cond do
      not Accounts.verified?(account) -> {:error, :not_verified}
      Accounts.minor?(account) -> {:error, :minor_live}
      true -> insert(account, attrs)
    end
  end

  defp insert(account, attrs) do
    key = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    id = Ecto.UUID.generate()

    post =
      %Post{
        author_id: account.id,
        media_status: :processing,
        media_path: "/" <> Live.path(%Live{id: id}) <> "/index.m3u8"
      }
      |> Post.changeset(%{"kind" => "live", "body" => attrs["body"]})

    Multi.new()
    |> Multi.insert(:post, post)
    |> Multi.insert(:live, fn %{post: post} ->
      %Live{
        id: id,
        post_id: post.id,
        account_id: account.id,
        key_hash: hash(key),
        status: :waiting
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{live: live}} -> {:ok, live, key}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Responde ao servidor de transmissão. `params` é o que o MediaMTX manda a
  cada conexão: ação, caminho, e a chave (na query, no token ou na senha).
  """
  def authorize(%{"action" => "publish", "path" => path} = params) do
    with {:ok, live} <- find(path),
         true <- live.status in [:waiting, :live],
         key when is_binary(key) <- key(params),
         true <- Plug.Crypto.secure_compare(hash(key), live.key_hash) do
      start(live)
    else
      _ -> :error
    end
  end

  def authorize(%{"action" => "read", "path" => path}) do
    case find(path) do
      {:ok, %Live{status: :live}} -> :ok
      _ -> :error
    end
  end

  def authorize(_params), do: :error

  defp find("ao-vivo/" <> id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Live{} = live <- Repo.get(Live, id) do
      {:ok, live}
    else
      _ -> :error
    end
  end

  defp find(_path), do: :error

  defp key(params) do
    query = URI.decode_query(params["query"] || "")

    Enum.find(
      [query["chave"], params["token"], params["password"]],
      &(is_binary(&1) and &1 != "")
    )
  end

  # Primeira conexão: a live entra no ar e o post aparece, com a hora de agora.
  defp start(%Live{status: :waiting} = live) do
    now = now()

    Repo.transaction(fn ->
      live |> Ecto.Changeset.change(status: :live, started_at: now) |> Repo.update!()

      Repo.update_all(from(p in Post, where: p.id == ^live.post_id),
        set: [media_status: :ready, inserted_at: now, updated_at: now]
      )
    end)

    :ok
  end

  # A conexão caiu e voltou: segue a mesma live.
  defp start(%Live{status: :live}), do: :ok

  def list_live, do: Repo.all(from l in Live, where: l.status == :live)

  @doc """
  A transmissão acabou: a live sai do ar e a gravação entra na fila. O
  servidor de transmissão leva alguns segundos para fechar o arquivo.
  """
  def finish(%Live{status: :live} = live) do
    Multi.new()
    |> Multi.update(:live, Ecto.Changeset.change(live, status: :ended, ended_at: now()))
    |> Multi.update_all(:post, from(p in Post, where: p.id == ^live.post_id),
      set: [media_status: :processing]
    )
    |> Oban.insert(:job, RecordingWorker.new(%{live_id: live.id}, schedule_in: 5))
    |> Repo.transaction()
  end

  @doc "Desfaz as lives abertas que nunca começaram."
  def expire_waiting(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@waiting_limit_seconds, :second)

    post_ids =
      Repo.all(
        from l in Live,
          where: l.status == :waiting and l.inserted_at < ^cutoff,
          select: l.post_id
      )

    Repo.delete_all(from p in Post, where: p.id in ^post_ids)
  end

  def get(id), do: Repo.get(Live, id)

  def recordings_dir,
    do: Application.get_env(:rede_social, :ao_vivo, [])[:recordings_dir] || "priv/gravacoes"

  defp hash(key), do: :crypto.hash(:sha256, key)
  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
