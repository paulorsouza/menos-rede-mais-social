defmodule RedeSocialWeb.SignedMediaTest do
  use RedeSocialWeb.ConnCase, async: true

  alias RedeSocial.Storage

  setup do
    key = "v/assinado-#{System.unique_integer([:positive])}/master.m3u8"
    :ok = Storage.put_binary(key, "#EXTM3U\n")
    %{key: key}
  end

  test "abre só com endereço assinado, no prazo, e sem cópia no navegador", %{
    conn: conn,
    key: key
  } do
    url = Storage.url("/media/" <> key)
    assert url =~ ~r{^/media/s/\d+/[A-Za-z0-9_-]+/v/}

    conn = get(conn, url)
    assert response(conn, 200) == "#EXTM3U\n"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "os pedaços do vídeo herdam a assinatura do caminho", %{conn: conn, key: key} do
    segment = String.replace(key, "master.m3u8", "360/seg1.ts")
    :ok = Storage.put_binary(segment, "pedaço")

    url =
      key |> then(&Storage.url("/media/" <> &1)) |> String.replace("master.m3u8", "360/seg1.ts")

    assert response(get(conn, url), 200) == "pedaço"
  end

  test "sem assinatura, vencido ou de outro vídeo, não abre", %{conn: conn, key: key} do
    assert response(get(conn, "/media/" <> key), 403)

    yesterday = DateTime.add(DateTime.utc_now(), -2, :day)
    assert response(get(conn, Storage.url("/media/" <> key, yesterday)), 403)

    other = Storage.url("/media/v/outro/master.m3u8")
    forged = String.replace(other, "v/outro/", Path.dirname(key) <> "/")
    assert response(get(conn, forged), 403)
  end

  test "a assinatura é a mesma que o secure_link do nginx confere" do
    "/media/s/" <> rest = Storage.url("/media/f/abc.webp")
    [expires, signature, "f", "abc.webp"] = String.split(rest, "/")

    expected =
      :crypto.hash(:md5, "#{expires}f/abc.webp segredo-de-teste")
      |> Base.url_encode64(padding: false)

    assert signature == expected
  end
end
