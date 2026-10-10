defmodule RedeSocial.MediaCaptionsTest do
  # Mexe na configuração do whisper, então não roda junto com os outros.
  use RedeSocial.DataCase, async: false
  use Oban.Testing, repo: RedeSocial.Repo

  import RedeSocial.{Fixtures, MediaFixtures}

  alias RedeSocial.{Media, Repo, Social, Storage}
  alias RedeSocial.Media.TranscodeWorker

  defp stored(path), do: Path.join(Storage.Local.root(), Storage.key(path))

  describe "legendas" do
    setup do
      Application.put_env(:rede_social, :whisper_url, "http://whisper")
      Application.put_env(:rede_social, :whisper_req_options, plug: {Req.Test, Media.Captions})

      on_exit(fn ->
        Application.delete_env(:rede_social, :whisper_url)
        Application.delete_env(:rede_social, :whisper_req_options)
      end)
    end

    test "o áudio vai para o whisper e a legenda fica junto do vídeo" do
      Req.Test.stub(Media.Captions, fn conn ->
        Plug.Conn.send_resp(conn, 200, "WEBVTT\n\n00:00.000 --> 00:02.000\nUm apito.\n")
      end)

      {:ok, post} = Social.create_post(account_fixture(), %{}, upload(vertical_video()))
      :ok = perform_job(TranscodeWorker, %{asset_id: post.media_asset_id})

      post = Repo.reload!(post)
      assert post.captions_path =~ ~r{/legendas\.vtt$}
      assert File.read!(stored(post.captions_path)) =~ "Um apito."
    end

    @tag :capture_log
    test "se o whisper falha, o vídeo fica no ar sem legenda" do
      Req.Test.stub(Media.Captions, &Plug.Conn.send_resp(&1, 500, "erro"))

      {:ok, post} = Social.create_post(account_fixture(), %{}, upload(vertical_video()))
      :ok = perform_job(TranscodeWorker, %{asset_id: post.media_asset_id})

      post = Repo.reload!(post)
      assert post.media_status == :ready
      assert post.captions_path == nil
    end
  end
end
