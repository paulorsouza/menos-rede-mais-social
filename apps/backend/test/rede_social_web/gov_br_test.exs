defmodule RedeSocialWeb.GovBrTest do
  use RedeSocialWeb.ConnCase, async: true

  alias RedeSocial.{Accounts, GovBr}
  alias RedeSocial.Accounts.CPF

  @issuer "https://sso.staging.acesso.gov.br/"

  # Uma chave como a que o gov.br publica em /jwk, com o mesmo `kid` do manual.
  setup do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_kty, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{key: key, jwks: %{"keys" => [Map.merge(public, %{"kid" => "rsa1", "alg" => "RS256"})]}}
  end

  defp id_token(key, claims) do
    claims =
      Map.merge(
        %{
          "iss" => @issuer,
          "aud" => "cliente-de-teste",
          "exp" => System.system_time(:second) + 60,
          "reliability_info" => %{"level" => "silver"},
          "name" => "Nome Que A Rede Ignora"
        },
        claims
      )

    {_jws, token} =
      key |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "rsa1"}, claims) |> JOSE.JWS.compact()

    token
  end

  defp stub_govbr(jwks, id_token) do
    Req.Test.stub(GovBr, fn conn ->
      case conn.request_path do
        "/token" -> Req.Test.json(conn, %{"access_token" => "x", "id_token" => id_token})
        "/jwk" -> Req.Test.json(conn, jwks)
      end
    end)
  end

  describe "identity/2" do
    test "tira do token só o CPF e o nível", %{key: key, jwks: jwks} do
      cpf = CPF.generate_for_testing()
      token = id_token(key, %{"sub" => cpf, "nonce" => "n1"})
      stub_govbr(jwks, token)

      assert GovBr.identity(token, %{"nonce" => "n1"}) ==
               {:ok, %{cpf: cpf, level: :prata, age_band: :minor}}
    end

    test "recusa token com nonce de outro login, vencido ou assinado por outra chave", c do
      cpf = CPF.generate_for_testing()
      stub_govbr(c.jwks, "")

      assert GovBr.identity(id_token(c.key, %{"sub" => cpf, "nonce" => "n1"}), %{"nonce" => "n2"}) ==
               {:error, :wrong_nonce}

      expired = id_token(c.key, %{"sub" => cpf, "nonce" => "n1", "exp" => 1})
      assert GovBr.identity(expired, %{"nonce" => "n1"}) == {:error, :expired}

      forged = id_token(JOSE.JWK.generate_key({:rsa, 2048}), %{"sub" => cpf, "nonce" => "n1"})
      assert GovBr.identity(forged, %{"nonce" => "n1"}) == {:error, :bad_signature}
    end
  end

  describe "ida e volta" do
    test "conta nova escolhe o apelido; na volta seguinte entra direto", %{conn: conn} = c do
      cpf = CPF.generate_for_testing()

      conn = get(conn, ~p"/api/govbr/entrar")

      query =
        conn |> redirected_to(302) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert query["code_challenge_method"] == "S256"
      assert query["scope"] =~ "govbr_confiabilidades_idtoken"

      stub_govbr(c.jwks, id_token(c.key, %{"sub" => cpf, "nonce" => query["nonce"]}))
      conn = conn |> recycle() |> get(~p"/api/govbr/retorno?code=abc&state=#{query["state"]}")
      assert redirected_to(conn) == "/entrar?govbr=apelido"

      conn = conn |> recycle() |> post(~p"/api/govbr/cadastro", %{nickname: "pessoa.govbr"})

      assert %{"account" => %{"nickname" => "pessoa.govbr", "govbr_level" => "prata"}} =
               json_response(conn, 201)

      account = Accounts.get_by_cpf(cpf)
      assert account.age_band == :minor
      assert account.cpf_ciphertext

      # Segunda vez: a conta já existe, então entra direto.
      conn = build_conn() |> get(~p"/api/govbr/entrar")

      query =
        conn |> redirected_to(302) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      stub_govbr(c.jwks, id_token(c.key, %{"sub" => cpf, "nonce" => query["nonce"]}))
      conn = conn |> recycle() |> get(~p"/api/govbr/retorno?code=abc&state=#{query["state"]}")
      assert redirected_to(conn) == "/"
    end

    test "volta com state de outro login não entra", %{conn: conn} do
      conn = get(conn, ~p"/api/govbr/entrar")
      conn = conn |> recycle() |> get(~p"/api/govbr/retorno?code=abc&state=forjado")
      assert redirected_to(conn) == "/entrar?govbr=erro"
    end
  end
end
