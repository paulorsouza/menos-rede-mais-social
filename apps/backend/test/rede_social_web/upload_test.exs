defmodule RedeSocialWeb.UploadTest do
  use RedeSocialWeb.ConnCase, async: true
  use Oban.Testing, repo: RedeSocial.Repo

  import RedeSocial.{Fixtures, MediaFixtures}

  alias RedeSocial.Accounts
  alias RedeSocial.Media.TranscodeWorker

  defp log_in(conn, account), do: Plug.Test.init_test_session(conn, %{account_id: account.id})

  defp tus(conn), do: put_req_header(conn, "tus-resumable", "1.0.0")

  defp open(conn, size, type \\ "video/mp4") do
    conn
    |> tus()
    |> put_req_header("upload-length", Integer.to_string(size))
    |> put_req_header(
      "upload-metadata",
      "filename #{Base.encode64("video.mp4")},filetype #{Base.encode64(type)}"
    )
    |> post(~p"/api/envios")
  end

  defp send_bytes(conn, location, offset, bytes) do
    conn
    |> tus()
    |> put_req_header("upload-offset", Integer.to_string(offset))
    |> put_req_header("content-type", "application/offset+octet-stream")
    |> patch(location, bytes)
  end

  defp offset(conn) do
    conn |> get_resp_header("upload-offset") |> List.first() |> String.to_integer()
  end

  test "o servidor diz que fala tus e qual o tamanho máximo", %{conn: conn} do
    conn = options(conn, ~p"/api/envios")

    assert response(conn, 204)
    assert get_resp_header(conn, "tus-version") == ["1.0.0"]
    assert get_resp_header(conn, "tus-extension") == ["creation,termination"]
    assert [max] = get_resp_header(conn, "tus-max-size")
    assert String.to_integer(max) > 1_000_000_000
  end

  test "o envio cai no meio, retoma de onde parou e vira post", %{conn: conn} do
    author = account_fixture()
    bytes = File.read!(vertical_video())
    half = div(byte_size(bytes), 2)
    conn = log_in(conn, author)

    created = open(conn, byte_size(bytes))
    assert response(created, 201)
    [location] = get_resp_header(created, "location")

    # Primeira metade, e a conexão "cai".
    first = send_bytes(conn, location, 0, binary_part(bytes, 0, half))
    assert response(first, 204)
    assert offset(first) == half

    # Ao voltar, o app pergunta quantos bytes chegaram.
    head = conn |> tus() |> head(location)
    assert response(head, 200)
    assert offset(head) == half
    assert get_resp_header(head, "upload-length") == [Integer.to_string(byte_size(bytes))]

    # Mandar de novo a partir do zero não passa: o offset não confere.
    assert response(send_bytes(conn, location, 0, bytes), 409)

    rest = send_bytes(conn, location, half, binary_part(bytes, half, byte_size(bytes) - half))
    assert response(rest, 204)
    assert offset(rest) == byte_size(bytes)

    id = location |> String.split("/") |> List.last()
    published = post(conn, ~p"/api/posts", %{"upload_id" => id, "body" => "Retomado"})
    post = json_response(published, 201)["post"]

    assert post["kind"] == "short"
    assert post["media_status"] == "processing"
    assert_enqueued(worker: TranscodeWorker)

    # O mesmo envio não vira dois posts.
    again = post(conn, ~p"/api/posts", %{"upload_id" => id, "body" => "De novo"})
    assert json_response(again, 422)["error"] =~ "não foi encontrado"
  end

  test "não publica com o envio pela metade", %{conn: conn} do
    conn = log_in(conn, account_fixture())
    [location] = conn |> open(100) |> get_resp_header("location")
    send_bytes(conn, location, 0, String.duplicate("a", 40))
    id = location |> String.split("/") |> List.last()

    assert json_response(post(conn, ~p"/api/posts", %{"upload_id" => id}), 409)["error"] =~
             "ainda não terminou"
  end

  test "o envio é só de quem abriu", %{conn: conn} do
    [location] = conn |> log_in(account_fixture()) |> open(100) |> get_resp_header("location")

    other = log_in(build_conn(), account_fixture())
    assert response(other |> tus() |> head(location), 404)
    assert response(send_bytes(other, location, 0, "abc"), 404)
  end

  test "não aceita mais bytes do que o tamanho combinado", %{conn: conn} do
    conn = log_in(conn, account_fixture())
    [location] = conn |> open(10) |> get_resp_header("location")

    assert json_response(send_bytes(conn, location, 0, String.duplicate("a", 20)), 413)
  end

  test "limites: tamanho, tipo de arquivo e conta verificada", %{conn: conn} do
    conn = log_in(conn, account_fixture())

    assert json_response(open(conn, 30_000_000, "image/jpeg"), 413)["error"] =~ "tamanho máximo"
    assert json_response(open(conn, 100, "application/zip"), 422)["error"] =~ "não aceito"

    {:ok, basic} = Accounts.register_basic(%{nickname: "so_le"})
    assert json_response(open(log_in(build_conn(), basic), 100), 403)
  end

  test "sem o cabeçalho do tus, o servidor avisa a versão", %{conn: conn} do
    conn =
      conn
      |> log_in(account_fixture())
      |> put_req_header("upload-length", "10")
      |> post(~p"/api/envios")

    assert response(conn, 412)
    assert get_resp_header(conn, "tus-version") == ["1.0.0"]
  end

  test "desistir apaga o envio", %{conn: conn} do
    conn = log_in(conn, account_fixture())
    [location] = conn |> open(100) |> get_resp_header("location")

    assert response(conn |> tus() |> delete(location), 204)
    assert response(conn |> tus() |> head(location), 404)
  end
end
