defmodule RedeSocial.MediaTest do
  use RedeSocial.DataCase, async: true
  use Oban.Testing, repo: RedeSocial.Repo

  import RedeSocial.{Fixtures, MediaFixtures}

  alias RedeSocial.{Media, Privacy, Repo, Social, Storage}
  alias RedeSocial.Media.{Asset, TranscodeWorker}

  defp stored(path), do: Path.join(Storage.Local.root(), Storage.key(path))

  describe "foto" do
    test "sai em WebP, sem o EXIF da câmera e com o lado maior limitado" do
      {:ok, post} =
        Social.create_post(account_fixture(), %{"kind" => "text"}, upload(photo_with_exif()))

      assert post.kind == :photo
      assert post.media_status == :ready
      assert post.media_path =~ ~r{^/media/f/.+\.webp$}

      file = File.read!(stored(post.media_path))
      refute file =~ exif_marker()

      {:ok, probe} = Media.FFmpeg.probe(stored(post.media_path))
      assert {probe.width, probe.height} == {2048, 683}
    end
  end

  describe "vídeo" do
    test "nasce processando, entra na fila e só o autor vê até ficar pronto" do
      author = account_fixture()
      other = account_fixture()

      {:ok, post} = Social.create_post(author, %{"body" => "Em pé"}, upload(vertical_video()))

      assert post.kind == :short
      assert post.media_status == :processing
      assert post.media_path == nil
      assert_enqueued(worker: TranscodeWorker, args: %{asset_id: post.media_asset_id})

      assert Social.get_post(post.id, author)
      refute Social.get_post(post.id, other)
      refute post.id in Enum.map(Social.candidates(other, [:short], 50), & &1.id)

      assert :ok = perform_job(TranscodeWorker, %{asset_id: post.media_asset_id})

      post = Social.get_post(post.id, other)
      assert post.media_status == :ready
      assert post.media_path =~ ~r{^/media/v/.+/master\.m3u8$}
      assert File.exists?(stored(post.media_path))
      assert File.exists?(stored(post.poster_path))
      assert post.duration_ms == 2000
      assert post.id in Enum.map(Social.candidates(other, [:short], 50), & &1.id)

      # Vídeo de 360 de largura: só os degraus até 360, e o original some.
      asset = Repo.get!(Asset, post.media_asset_id)
      assert Enum.map(asset.renditions, & &1["short_side"]) == [240, 360]
      assert Enum.all?(asset.renditions, &(&1["bytes"] > 0))
      assert asset.cpu_ms > 0
      assert asset.stored_bytes > 0
      assert asset.source_path == nil
    end

    test "o tipo sai do arquivo: deitado é vídeo, mesmo que o app diga short" do
      {:ok, post} =
        Social.create_post(account_fixture(), %{"kind" => "short"}, upload(landscape_video()))

      assert post.kind == :video
    end

    test "short é em pé e curto; em pé e longo é vídeo" do
      assert Media.kind_for(%{type: :video, width: 720, height: 1280, duration_ms: 60_000}) ==
               :short

      assert Media.kind_for(%{type: :video, width: 720, height: 1280, duration_ms: 600_000}) ==
               :video

      # Gravado no navegador, sem duração: vale a orientação.
      assert Media.kind_for(%{type: :video, width: 720, height: 1280, duration_ms: nil}) ==
               :short

      assert Media.kind_for(%{type: :video, width: 1280, height: 720, duration_ms: 10_000}) ==
               :video
    end

    test "sem o original, a conversão desiste e o post fica marcado" do
      {:ok, post} = Social.create_post(account_fixture(), %{}, upload(vertical_video()))
      File.rm!(Repo.get!(Asset, post.media_asset_id).source_path)

      assert {:cancel, :no_source} =
               perform_job(TranscodeWorker, %{asset_id: post.media_asset_id})

      assert Repo.reload!(post).media_status == :failed
    end

    test "apagar a conta apaga os arquivos do vídeo" do
      author = account_fixture()
      {:ok, post} = Social.create_post(author, %{}, upload(vertical_video()))
      :ok = perform_job(TranscodeWorker, %{asset_id: post.media_asset_id})
      master = stored(Repo.reload!(post).media_path)
      assert File.exists?(master)

      :ok = Privacy.delete_account(author, author.nickname)

      refute File.exists?(master)
    end
  end
end
