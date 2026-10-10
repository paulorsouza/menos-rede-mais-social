defmodule RedeSocial.LivesTest do
  # Mexe na configuração das lives (segredo e pasta das gravações).
  use RedeSocialWeb.ConnCase, async: false
  use Oban.Testing, repo: RedeSocial.Repo

  import RedeSocial.{Fixtures, MediaFixtures}

  alias RedeSocial.{Accounts, Lives, Repo, Social}
  alias RedeSocial.Lives.{Live, RecordingWorker}
  alias RedeSocial.Social.Post

  @recordings "tmp/test_gravacoes"

  setup do
    Application.put_env(:rede_social, :ao_vivo,
      api: "http://ao-vivo",
      secret: "segredo-de-teste",
      recordings_dir: @recordings
    )

    on_exit(fn -> Application.delete_env(:rede_social, :ao_vivo) end)
  end

  defp publish(live, key),
    do:
      Lives.authorize(%{
        "action" => "publish",
        "path" => Live.path(live),
        "query" => "chave=#{key}"
      })

  defp read(live), do: Lives.authorize(%{"action" => "read", "path" => Live.path(live)})

  test "a live só aparece para os outros quando a transmissão começa" do
    author = account_fixture()
    other = account_fixture()
    {:ok, live, key} = Lives.create(author, %{"body" => "Ao vivo da feira"})

    post = Repo.get!(Post, live.post_id)
    assert post.kind == :live
    refute Social.get_post(post.id, other)
    assert read(live) == :error

    assert publish(live, "chave-errada") == :error
    assert publish(live, key) == :ok

    assert Social.get_post(post.id, other)
    assert Repo.reload!(live).status == :live
    assert read(live) == :ok
    assert post.id in Enum.map(Social.candidates(other, [:live], 10), & &1.id)

    # A conexão caiu e voltou: continua a mesma live.
    assert publish(live, key) == :ok
  end

  test "a chave também vale como token (o que o navegador manda no WHIP)" do
    {:ok, live, key} = Lives.create(account_fixture(), %{})

    assert Lives.authorize(%{"action" => "publish", "path" => Live.path(live), "token" => key}) ==
             :ok
  end

  test "menor de idade e conta básica não fazem live" do
    assert Lives.create(account_fixture(age_band: :minor), %{}) == {:error, :minor_live}

    {:ok, basic} = Accounts.register_basic(%{nickname: "so_assiste"})
    assert Lives.create(basic, %{}) == {:error, :not_verified}
  end

  test "quando acaba, a gravação vira vídeo pelo caminho de sempre" do
    author = account_fixture()
    {:ok, live, key} = Lives.create(author, %{"body" => "Gravada"})
    :ok = publish(live, key)
    {:ok, _} = Lives.finish(Repo.reload!(live))

    assert Repo.get!(Post, live.post_id).media_status == :processing
    assert_enqueued(worker: RecordingWorker, args: %{live_id: live.id})

    dir = Path.join(@recordings, Live.path(live))
    File.mkdir_p!(dir)
    File.cp!(vertical_video(), Path.join(dir, "2026-10-10_12-00-00-000000.mp4"))

    assert :ok = perform_job(RecordingWorker, %{live_id: live.id})

    post = Repo.get!(Post, live.post_id)
    assert post.kind == :short
    assert post.media_status == :ready
    assert post.media_path =~ ~r{^/media/v/.+/master\.m3u8$}
    refute File.exists?(dir)
  end

  test "live que acaba sem gravação nenhuma some" do
    {:ok, live, key} = Lives.create(account_fixture(), %{})
    :ok = publish(live, key)
    {:ok, _} = Lives.finish(Repo.reload!(live))

    assert :ok = perform_job(RecordingWorker, %{live_id: live.id})
    refute Repo.get(Post, live.post_id)
  end

  test "live aberta que não começou em uma hora é desfeita" do
    {:ok, live, _key} = Lives.create(account_fixture(), %{})

    Lives.expire_waiting(DateTime.add(DateTime.utc_now(), 2, :hour))

    refute Repo.get(Post, live.post_id)
  end

  describe "API" do
    defp log_in(conn, account), do: Plug.Test.init_test_session(conn, %{account_id: account.id})

    test "abrir a live devolve o caminho do navegador e o do OBS", %{conn: conn} do
      body =
        conn
        |> log_in(account_fixture())
        |> post(~p"/api/lives", %{body: "Oi"})
        |> json_response(201)

      assert %{"whip_url" => "/whip/ao-vivo/" <> _, "rtmp" => %{"stream_key" => stream_key}} =
               body["live"]

      assert stream_key =~ "?chave="
    end

    test "o servidor de transmissão só é atendido com o segredo", %{conn: conn} do
      {:ok, live, key} = Lives.create(account_fixture(), %{})
      payload = %{"action" => "publish", "path" => Live.path(live), "query" => "chave=#{key}"}

      assert response(post(conn, "/api/ao-vivo/autorizar?segredo=errado", payload), 401)

      assert response(
               post(build_conn(), "/api/ao-vivo/autorizar?segredo=segredo-de-teste", payload),
               200
             )
    end
  end
end
