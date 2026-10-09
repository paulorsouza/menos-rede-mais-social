defmodule RedeSocial.GovBr do
  @moduledoc """
  Login Único do gov.br, por OpenID Connect com PKCE, como no roteiro de
  integração oficial (acesso.gov.br/roteiro-tecnico).

  1. `authorize_url/1` manda a pessoa para o gov.br com `state`, `nonce` e o
     desafio PKCE, que o backend guarda na sessão.
  2. Na volta, `exchange/2` troca o código pelos tokens.
  3. `identity/2` confere o id_token (assinatura RS256 pelas chaves de /jwk,
     emissor, audiência, validade e nonce) e tira dele só o que a rede usa:
     o CPF (claim `sub`) e o nível da conta (`reliability_info.level`).

  O nome, o e-mail, o telefone e a foto que o gov.br manda são ignorados: o
  perfil usa apelido, e a rede não guarda nada disso.

  O Login Único não informa a data de nascimento. Enquanto não houver uma
  fonte confiável de idade, a faixa vem de `:age_fallback`, que por padrão é
  `:minor`: na dúvida, a conta fica com as proteções de menor de idade.

  Sem `client_id` configurado, o login de verdade fica desligado e só o
  simulado da demonstração funciona.
  """

  @scope "openid email profile govbr_confiabilidades govbr_confiabilidades_idtoken"
  @levels %{"bronze" => :bronze, "silver" => :prata, "gold" => :ouro}

  def enabled?, do: config(:client_id) not in [nil, ""]

  @doc "Valores de uso único do login: state, nonce e o verificador PKCE."
  def new_flow do
    %{
      "state" => random(32),
      "nonce" => random(32),
      "verifier" => random(48),
      "started_at" => System.system_time(:second)
    }
  end

  def authorize_url(%{"state" => state, "nonce" => nonce, "verifier" => verifier}) do
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    query =
      URI.encode_query(%{
        response_type: "code",
        client_id: config(:client_id),
        scope: @scope,
        redirect_uri: config(:redirect_uri),
        nonce: nonce,
        state: state,
        code_challenge: challenge,
        code_challenge_method: "S256"
      })

    config(:base_url) <> "/authorize?" <> query
  end

  @doc "Troca o código da volta do gov.br pelo id_token."
  def exchange(code, %{"verifier" => verifier}) do
    basic = Base.encode64("#{config(:client_id)}:#{config(:client_secret)}")

    case Req.post(client(),
           url: "/token",
           headers: [{"authorization", "Basic " <> basic}],
           form: [
             grant_type: "authorization_code",
             code: code,
             redirect_uri: config(:redirect_uri),
             code_verifier: verifier
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"id_token" => id_token}}} -> {:ok, id_token}
      {:ok, %Req.Response{status: status}} -> {:error, {:token, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Confere o id_token e devolve `%{cpf: ..., level: ..., age_band: ...}`.
  """
  def identity(id_token, %{"nonce" => nonce}) do
    with {:ok, claims} <- verify(id_token),
         :ok <- check(claims, nonce),
         {:ok, cpf} <- cpf(claims),
         {:ok, level} <- level(claims) do
      {:ok, %{cpf: cpf, level: level, age_band: config(:age_fallback) || :minor}}
    end
  end

  defp verify(id_token) do
    with {:ok, %{"keys" => keys}} <- jwks(),
         {:ok, kid} <- kid(id_token),
         %{} = key <- Enum.find(keys, &(&1["kid"] == kid)) || {:error, :unknown_key} do
      case JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["RS256"], id_token) do
        {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
        _ -> {:error, :bad_signature}
      end
    end
  end

  defp kid(id_token) do
    case JOSE.JWT.peek_protected(id_token) do
      %JOSE.JWS{fields: %{"kid" => kid}} -> {:ok, kid}
      _ -> {:error, :no_kid}
    end
  rescue
    _ -> {:error, :malformed_token}
  end

  defp check(claims, nonce) do
    issuer = String.trim_trailing(config(:base_url), "/")
    now = System.system_time(:second)

    cond do
      String.trim_trailing(claims["iss"] || "", "/") != issuer -> {:error, :wrong_issuer}
      not audience?(claims["aud"]) -> {:error, :wrong_audience}
      not is_integer(claims["exp"]) or claims["exp"] < now -> {:error, :expired}
      claims["nonce"] != nonce -> {:error, :wrong_nonce}
      true -> :ok
    end
  end

  defp audience?(aud) when is_binary(aud), do: aud == config(:client_id)
  defp audience?(aud) when is_list(aud), do: config(:client_id) in aud
  defp audience?(_aud), do: false

  defp cpf(%{"sub" => sub}) when is_binary(sub) do
    digits = String.replace(sub, ~r/\D/, "")
    if String.length(digits) == 11, do: {:ok, digits}, else: {:error, :no_cpf}
  end

  defp cpf(_claims), do: {:error, :no_cpf}

  defp level(%{"reliability_info" => %{"level" => level}}) do
    case Map.fetch(@levels, level) do
      {:ok, level} -> {:ok, level}
      :error -> {:error, :unknown_level}
    end
  end

  defp level(_claims), do: {:error, :unknown_level}

  defp jwks do
    case Req.get(client(), url: "/jwk") do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:jwk, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp client do
    Req.new(base_url: config(:base_url), retry: false, receive_timeout: 10_000)
    |> Req.merge(Application.get_env(:rede_social, :govbr_req_options, []))
  end

  defp config(key), do: :rede_social |> Application.get_env(:govbr, []) |> Keyword.get(key)

  defp random(bytes),
    do: bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
