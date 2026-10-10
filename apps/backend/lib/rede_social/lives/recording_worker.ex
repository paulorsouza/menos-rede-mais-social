defmodule RedeSocial.Lives.RecordingWorker do
  @moduledoc """
  Quando a live acaba, junta a gravação e converte pelo mesmo caminho de
  qualquer vídeo enviado. O post deixa de ser live e vira vídeo ou short,
  com as curtidas que já tinha. Live sem gravação nenhuma (a conexão nem
  chegou a mandar imagem) some.
  """
  use Oban.Worker, queue: :video, max_attempts: 3

  require Logger

  alias RedeSocial.{Lives, Media, Repo, Uploads}
  alias RedeSocial.Lives.Live
  alias RedeSocial.Media.FFmpeg
  alias RedeSocial.Social.Post

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"live_id" => id}}) do
    with %Live{} = live <- Lives.get(id),
         %Post{} = post <- Repo.get(Post, live.post_id) do
      dir = Path.join(Lives.recordings_dir(), Live.path(live))

      case dir |> Path.join("*.mp4") |> Path.wildcard() |> Enum.sort() do
        [] ->
          Logger.info("a live #{live.id} acabou sem gravação; o post sai do ar")
          Repo.delete(post)
          :ok

        parts ->
          with {:ok, source} <- join(parts, live),
               {:ok, fields} <- Media.ingest_now(live.account_id, source) do
            post |> Ecto.Changeset.change(fields) |> Repo.update!()
            File.rm_rf(dir)
            :ok
          end
      end
    else
      nil -> {:cancel, :not_found}
    end
  end

  # A gravação vem em pedaços de até uma hora (infra/ao-vivo/mediamtx.yml).
  defp join(parts, live) do
    File.mkdir_p!(Uploads.staging_dir())
    target = Path.join(Uploads.staging_dir(), "gravacao-#{live.id}.mp4")

    case parts do
      [single] -> with :ok <- File.cp(single, target), do: {:ok, target}
      many -> FFmpeg.concat(many, target)
    end
  end

  # Uma live longa leva tempo para converter.
  @impl Oban.Worker
  def timeout(_job), do: :timer.hours(2)
end
