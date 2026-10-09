defmodule RedeSocial.SocialTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Accounts, Social}

  defp video_upload do
    path = Path.join(System.tmp_dir!(), "video#{System.unique_integer([:positive])}.mp4")
    File.write!(path, "não é um vídeo de verdade")
    %Plug.Upload{path: path, filename: "video.mp4", content_type: "video/mp4"}
  end

  describe "create_post/3" do
    test "conta básica não publica" do
      {:ok, basic} = Accounts.register_basic(%{nickname: "so_leitura"})
      attrs = %{"kind" => "text", "body" => "oi"}

      assert Social.create_post(basic, attrs) == {:error, :not_verified}
    end

    test "texto curto tem no máximo 140 caracteres" do
      attrs = %{"kind" => "text", "body" => String.duplicate("a", 141)}
      {:error, changeset} = Social.create_post(account_fixture(), attrs)

      assert "no máximo 140 caracteres" in errors_on(changeset).body
    end

    test "o post não tem tema nem tag, nem se alguém mandar" do
      attrs = %{"kind" => "text", "body" => "Pão de queijo saindo", "topics" => ["politica"]}

      {:ok, post} = Social.create_post(account_fixture(), attrs)

      refute Map.has_key?(post, :topics)
    end

    test "só prata ou ouro ligam anúncio no vídeo" do
      attrs = %{"kind" => "video", "body" => "x", "ad_markers" => ["start"]}

      {:ok, bronze_post} =
        Social.create_post(account_fixture(govbr_level: :bronze), attrs, video_upload())

      {:ok, prata_post} =
        Social.create_post(account_fixture(govbr_level: :prata), attrs, video_upload())

      refute bronze_post.monetized
      assert bronze_post.ad_markers == []
      assert prata_post.monetized
      assert prata_post.ad_markers == ["start"]
      assert String.starts_with?(prata_post.media_path, "/uploads/")
    end

    test "a descrição da imagem fica só em foto" do
      path = Path.join(System.tmp_dir!(), "foto#{System.unique_integer([:positive])}.png")
      File.write!(path, "não é uma foto de verdade")
      upload = %Plug.Upload{path: path, filename: "foto.png", content_type: "image/png"}
      alt = "Um cachorro dormindo no sofá"

      {:ok, photo} =
        Social.create_post(account_fixture(), %{"kind" => "photo", "alt_text" => alt}, upload)

      {:ok, text} =
        Social.create_post(account_fixture(), %{
          "kind" => "text",
          "body" => "oi",
          "alt_text" => alt
        })

      assert photo.alt_text == alt
      assert text.alt_text == nil
    end

    test "recusa arquivo que não é foto nem vídeo" do
      upload = %{video_upload() | filename: "programa.exe"}
      attrs = %{"kind" => "short", "body" => "x"}

      assert Social.create_post(account_fixture(), attrs, upload) == {:error, :unsupported_file}
    end
  end

  describe "graph_edges/2" do
    test "liga quem curtiu e assistiu, perto da pessoa e nos candidatos" do
      viewer = account_fixture()
      neighbor = account_fixture()
      stranger = account_fixture()
      nobody = account_fixture()

      shared = post_fixture(account_fixture())
      seen_by_neighbor = post_fixture(account_fixture())
      candidate = post_fixture(account_fixture())
      far = post_fixture(account_fixture())
      watched = short_fixture(account_fixture())

      {:ok, true} = Social.toggle_like(viewer, shared)
      {:ok, true} = Social.toggle_like(neighbor, shared)
      {:ok, true} = Social.toggle_like(neighbor, seen_by_neighbor)
      {:ok, true} = Social.toggle_like(stranger, candidate)
      {:ok, true} = Social.toggle_like(nobody, far)
      :ok = Social.record_view(viewer, watched, 4_000)
      :ok = Social.record_view(viewer, watched, 12_000)

      edges = Social.graph_edges(viewer, [candidate.id])
      links = MapSet.new(edges, &{&1.user_id, &1.post_id, &1.kind})

      assert MapSet.member?(links, {viewer.id, shared.id, "like"})
      # Quem curtiu o mesmo que a pessoa entra com tudo o que fez.
      assert MapSet.member?(links, {neighbor.id, seen_by_neighbor.id, "like"})
      assert MapSet.member?(links, {stranger.id, candidate.id, "like"})
      refute MapSet.member?(links, {nobody.id, far.id, "like"})

      # Várias views do mesmo vídeo viram uma ligação só, com o maior tempo.
      assert [%{watched_ms: 12_000}] = Enum.filter(edges, &(&1.kind == "watch"))
    end

    test "descurtir tira a ligação" do
      viewer = account_fixture()
      post = post_fixture(account_fixture())

      {:ok, true} = Social.toggle_like(viewer, post)
      {:ok, false} = Social.toggle_like(viewer, post)

      assert Social.graph_edges(viewer, [post.id]) == []
    end

    test "ninguém se liga ao próprio post" do
      author = account_fixture()
      short = short_fixture(author)

      {:ok, true} = Social.toggle_like(author, short)
      :ok = Social.record_view(author, short, 30_000)

      assert Social.graph_edges(author, [short.id]) == []
    end
  end

  describe "record_view/3" do
    test "conta para o criador só com 2 segundos ou mais, e nunca a própria view" do
      author = account_fixture()
      viewer = account_fixture()
      post = short_fixture(author)

      :ok = Social.record_view(viewer, post, 1_500)
      :ok = Social.record_view(author, post, 9_000)
      assert Social.monthly_views(author) == 0

      :ok = Social.record_view(viewer, post, 2_000)
      assert Social.monthly_views(author) == 1
    end
  end

  describe "toggle_follow/2" do
    test "não deixa seguir a si mesmo" do
      account = account_fixture()
      assert Social.toggle_follow(account, account) == {:error, :self_follow}
    end
  end
end
