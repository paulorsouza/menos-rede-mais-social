defmodule RedeSocial.StorageS3Test do
  # Troca a configuração do armazenamento, então não roda junto com os outros.
  use ExUnit.Case, async: false

  alias RedeSocial.Storage.S3

  setup do
    previous = Application.get_env(:rede_social, RedeSocial.Storage)

    Application.put_env(:rede_social, RedeSocial.Storage,
      adapter: S3,
      endpoint: "http://garage:3900",
      bucket: "midia",
      region: "garage",
      access_key_id: "GK0000",
      secret_access_key: "segredo",
      req_options: [plug: {Req.Test, S3}, retry: false]
    )

    on_exit(fn -> Application.put_env(:rede_social, RedeSocial.Storage, previous) end)
  end

  test "guarda com o tipo do arquivo e a assinatura da AWS" do
    Req.Test.stub(S3, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/midia/v/abc/master.m3u8"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/vnd.apple.mpegurl"]
      assert [authorization] = Plug.Conn.get_req_header(conn, "authorization")
      assert authorization =~ "AWS4-HMAC-SHA256 Credential=GK0000/"
      assert {:ok, "#EXTM3U", conn} = Plug.Conn.read_body(conn)
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert RedeSocial.Storage.put_binary("v/abc/master.m3u8", "#EXTM3U") == :ok
  end

  test "lê um arquivo, e o que não existe volta como não encontrado" do
    Req.Test.stub(S3, fn conn ->
      assert conn.method == "GET"

      case conn.request_path do
        "/midia/v/abc/legendas.vtt" -> Plug.Conn.send_resp(conn, 200, "WEBVTT\n")
        _ -> Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    assert RedeSocial.Storage.get("v/abc/legendas.vtt") == {:ok, "WEBVTT\n"}
    assert RedeSocial.Storage.get("v/abc/outra.vtt") == {:error, :not_found}
  end

  test "lista todas as páginas de um prefixo" do
    Req.Test.stub(S3, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["prefix"] == "v/abc/"

      body =
        case conn.query_params["continuation-token"] do
          nil ->
            "<ListBucketResult><Contents><Key>v/abc/1.m4s</Key></Contents>" <>
              "<NextContinuationToken>pagina2</NextContinuationToken></ListBucketResult>"

          "pagina2" ->
            "<ListBucketResult><Contents><Key>v/abc/a&amp;b.m4s</Key></Contents></ListBucketResult>"
        end

      Plug.Conn.send_resp(conn, 200, body)
    end)

    assert S3.list("v/abc/") == {:ok, ["v/abc/1.m4s", "v/abc/a&b.m4s"]}
  end

  test "erro do armazenamento volta como erro, sem fingir que guardou" do
    Req.Test.stub(S3, &Plug.Conn.send_resp(&1, 403, "AccessDenied"))

    assert {:error, {:s3, 403, _}} = RedeSocial.Storage.put_binary("f/x.webp", "x")
  end
end
