defmodule RedeSocialWeb.FallbackController do
  use RedeSocialWeb, :controller

  alias RedeSocialWeb.Present

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: Present.errors(changeset)})
  end

  def call(conn, {:error, :not_found}), do: error(conn, :not_found, "Não encontrado.")
  def call(conn, nil), do: error(conn, :not_found, "Não encontrado.")

  def call(conn, {:error, :not_verified}) do
    error(conn, :forbidden, "Só contas verificadas pelo gov.br podem publicar.")
  end

  def call(conn, {:error, :invalid_cpf}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{cpf: ["CPF inválido"]}})
  end

  def call(conn, {:error, :unsupported_file}) do
    error(conn, :unprocessable_entity, "Formato de arquivo não aceito.")
  end

  def call(conn, {:error, :self_follow}) do
    error(conn, :unprocessable_entity, "Você não pode seguir a si mesmo.")
  end

  def call(conn, {:error, :no_shorts}) do
    error(conn, :unprocessable_entity, "O anúncio precisa dos shorts que vieram antes dele.")
  end

  def call(conn, {:error, :engine_unavailable}) do
    error(conn, :service_unavailable, "O motor de anúncios está fora do ar.")
  end

  def call(conn, {:error, :own_post}) do
    error(conn, :unprocessable_entity, "Você não pode denunciar o próprio post.")
  end

  def call(conn, {:error, :invalid_rule}) do
    error(conn, :unprocessable_entity, "Escolha uma das regras de conteúdo.")
  end

  def call(conn, {:error, :already_removed}) do
    error(conn, :conflict, "Este post já foi removido.")
  end

  def call(conn, {:error, :not_removed}) do
    error(conn, :unprocessable_entity, "Este post não foi removido.")
  end

  def call(conn, {:error, :already_appealed}) do
    error(conn, :conflict, "Você já recorreu desta remoção.")
  end

  def call(conn, {:error, :already_decided}) do
    error(conn, :conflict, "Este recurso já foi decidido.")
  end

  def call(conn, {:error, :invalid_outcome}) do
    error(conn, :unprocessable_entity, "Decida entre devolver o post ou manter a remoção.")
  end

  def call(conn, {:error, :same_moderator}) do
    error(
      conn,
      :forbidden,
      "Quem removeu o post não pode julgar o recurso. Outra pessoa da moderação precisa decidir."
    )
  end

  def call(conn, {:error, :confirmation}) do
    error(conn, :unprocessable_entity, "Digite o seu apelido para confirmar.")
  end

  def call(conn, {:error, :vault_unavailable}) do
    error(
      conn,
      :service_unavailable,
      "Não foi possível proteger o CPF agora, então a conta não foi criada. Tente de novo em instantes."
    )
  end

  def call(conn, {:error, :no_sealed_cpf}) do
    error(
      conn,
      :unprocessable_entity,
      "Esta conta não tem CPF guardado: ela não entrou pelo gov.br."
    )
  end

  def call(conn, {:error, :not_legal_officer}) do
    error(conn, :forbidden, "Só o setor jurídico da entidade gestora pode fazer isso.")
  end

  def call(conn, {:error, :already_opened}) do
    error(conn, :conflict, "Esta ordem já foi aberta.")
  end

  def call(conn, {:error, :invalid_guardian}) do
    error(conn, :unprocessable_entity, "Guardião desconhecido.")
  end

  def call(conn, {:error, {:missing_partial, key}}) do
    error(conn, :unprocessable_entity, "Falta a parte do item #{key}.")
  end

  def call(conn, {:error, {:bad_partial, key}}) do
    error(
      conn,
      :unprocessable_entity,
      "A parte do item #{key} não confere com a chave do guardião."
    )
  end

  def call(conn, {:error, :not_enough_guardians}) do
    error(conn, :unprocessable_entity, "Ainda não chegaram as partes de guardiões suficientes.")
  end

  def call(conn, {:error, :govbr_disabled}) do
    error(
      conn,
      :service_unavailable,
      "O login pelo gov.br ainda não está configurado neste servidor."
    )
  end

  def call(conn, {:error, :govbr_expired}) do
    error(
      conn,
      :unprocessable_entity,
      "Passou o tempo para escolher o apelido. Entre com o gov.br de novo."
    )
  end

  def call(conn, {:error, :not_moderator}) do
    error(conn, :forbidden, "Só a equipe de moderação pode fazer isso.")
  end

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
