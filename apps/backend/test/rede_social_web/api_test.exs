defmodule RedeSocialWeb.ApiTest do
  use RedeSocialWeb.ConnCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.Accounts
  alias RedeSocial.Accounts.CPF
  alias RedeSocial.Engine

  defp log_in(conn, account), do: Plug.Test.init_test_session(conn, %{account_id: account.id})

  test "sem login, o feed pede para entrar", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/feed"), 401)["error"] =~ "Entre"
  end

  test "entrar como pessoa da demonstração e ver a própria conta", %{conn: conn} do
    account_fixture(nickname: "maria.teste")

    conn = post(conn, ~p"/api/session", %{nickname: "maria.teste"})
    assert json_response(conn, 200)["account"]["nickname"] == "maria.teste"

    me = conn |> recycle() |> get(~p"/api/me") |> json_response(200)
    assert me["account"]["can_publish"]
    assert me["account"]["govbr_level"] == "prata"
  end

  test "apelido que não existe não entra", %{conn: conn} do
    assert json_response(post(conn, ~p"/api/session", %{nickname: "ninguem"}), 404)
  end

  test "cadastro pelo gov.br simulado não aceita o mesmo CPF duas vezes", %{conn: conn} do
    params = %{
      cpf: CPF.generate_for_testing(),
      nickname: "nova.pessoa",
      govbr_level: "prata",
      age_band: "adult",
      region: "Recife/PE"
    }

    assert json_response(post(conn, ~p"/api/govbr-simulado/cadastro", params), 201)

    conn = post(build_conn(), ~p"/api/govbr-simulado/cadastro", %{params | nickname: "outra"})

    assert json_response(conn, 422)["errors"]["cpf_fingerprint"] ==
             ["já existe uma conta para esta pessoa"]
  end

  test "o perfil público não mostra o nível do gov.br", %{conn: conn} do
    account_fixture(nickname: "perfil.publico", govbr_level: :ouro)

    account = conn |> get(~p"/api/accounts/perfil.publico") |> json_response(200)

    assert account["account"]["verified"]
    refute Map.has_key?(account["account"], "govbr_level")
  end

  test "conta básica não publica", %{conn: conn} do
    {:ok, basic} = Accounts.register_basic(%{nickname: "leitora"})

    conn =
      conn
      |> log_in(basic)
      |> post(~p"/api/posts", %{kind: "text", body: "oi"})

    assert json_response(conn, 403)["error"] =~ "verificadas"
  end

  test "publicar um texto e curtir", %{conn: conn} do
    author = account_fixture()

    created =
      conn
      |> log_in(author)
      |> post(~p"/api/posts", %{kind: "text", body: "Bom dia"})
      |> json_response(201)

    refute Map.has_key?(created["post"], "topics")

    liked =
      build_conn()
      |> log_in(account_fixture())
      |> post(~p"/api/posts/#{created["post"]["id"]}/like")
      |> json_response(200)

    assert %{"liked" => true, "likes" => 1} = liked
  end

  test "o feed vem na ordem do motor", %{conn: conn} do
    viewer = account_fixture()
    post = post_fixture(account_fixture())

    Req.Test.stub(Engine, fn conn ->
      Req.Test.json(conn, %{
        "items" => [
          %{"post_id" => post.id, "score" => 1, "reasons" => [%{"kind" => "public_ranking"}]}
        ],
        "engine_version" => "0.1.0",
        "engine_build" => "dev",
        "params_version" => 1,
        "params_sha256" => "abc"
      })
    end)

    feed = conn |> log_in(viewer) |> get(~p"/api/feed?mode=public_ranking") |> json_response(200)

    assert [%{"id" => id, "reasons" => [%{"kind" => "public_ranking"}]}] = feed["items"]
    assert id == post.id
    assert feed["engine"]["status"] == "ok"
  end

  test "em alta traz todo tipo de post", %{conn: conn} do
    text = post_fixture(account_fixture())
    short = short_fixture(account_fixture())
    test_pid = self()

    Req.Test.stub(Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:candidates, Jason.decode!(body)["candidates"]})

      Req.Test.json(conn, %{
        "items" => [],
        "engine_version" => "0.1.0",
        "engine_build" => "dev",
        "params_version" => 2,
        "params_sha256" => "abc"
      })
    end)

    conn
    |> log_in(account_fixture())
    |> get(~p"/api/feed?mode=public_ranking&kind=all")
    |> json_response(200)

    assert_received {:candidates, candidates}
    ids = Enum.map(candidates, & &1["post_id"])
    assert text.id in ids
    assert short.id in ids
  end

  test "denúncia, remoção, aviso e recurso pela API", %{conn: conn} do
    author = account_fixture()
    post = post_fixture(author, body: "PROMOÇÃO: mande o código do SMS")
    moderator = moderator_fixture()

    conn
    |> log_in(account_fixture())
    |> post(~p"/api/posts/#{post.id}/report", %{rule: 6})
    |> json_response(200)

    assert build_conn()
           |> log_in(account_fixture())
           |> get(~p"/api/moderation/queue")
           |> json_response(403)

    queue =
      build_conn() |> log_in(moderator) |> get(~p"/api/moderation/queue") |> json_response(200)

    assert [%{"total" => 1, "reports" => [%{"rule" => 6, "title" => "Golpe"}]}] = queue["reports"]

    build_conn()
    |> log_in(moderator)
    |> post(~p"/api/moderation/posts/#{post.id}/remove", %{rule: 6})
    |> json_response(200)

    me = build_conn() |> log_in(author) |> get(~p"/api/me") |> json_response(200)
    assert me["account"]["unread_notices"] == 1

    notices = build_conn() |> log_in(author) |> get(~p"/api/me/notices") |> json_response(200)

    assert [%{"kind" => "removed", "can_appeal" => true, "rule" => %{"number" => 6}}] =
             notices["notices"]

    build_conn()
    |> log_in(author)
    |> post(~p"/api/posts/#{post.id}/appeal", %{text: "Era uma piada."})
    |> json_response(201)

    queue =
      build_conn() |> log_in(moderator) |> get(~p"/api/moderation/queue") |> json_response(200)

    assert [%{"text" => "Era uma piada.", "rule" => %{"number" => 6}}] = queue["appeals"]
  end

  test "modo de feed desconhecido", %{conn: conn} do
    conn = conn |> log_in(account_fixture()) |> get(~p"/api/feed?mode=secreto")
    assert json_response(conn, 400)["error"] =~ "desconhecido"
  end

  test "a transparência mostra os parâmetros do motor", %{conn: conn} do
    Req.Test.stub(Engine, fn conn ->
      Req.Test.json(conn, %{
        "engine_version" => "0.1.0",
        "feed_params" => %{"path" => "params/feed.toml", "sha256" => "abc", "version" => 1}
      })
    end)

    report = conn |> get(~p"/api/transparency") |> json_response(200)

    assert report["engine"]["status"] == "ok"
    assert report["engine"]["feed_params"]["sha256"] == "abc"
    assert is_list(report["ads"])
  end
end
