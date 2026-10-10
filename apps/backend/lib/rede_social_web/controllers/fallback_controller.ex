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

  def call(conn, {:error, %{} = field_errors}) when not is_struct(field_errors) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: field_errors})
  end

  def call(conn, {:error, :pix_key_not_yours}) do
    error(conn, :unprocessable_entity, "Essa chave PIX não está no seu CPF. Use uma chave sua.")
  end

  def call(conn, {:error, :pix_key_not_found}) do
    error(conn, :unprocessable_entity, "Essa chave não existe no PIX.")
  end

  def call(conn, {:error, :cpf_pix_key}) do
    error(
      conn,
      :unprocessable_entity,
      "Use e-mail, celular ou chave aleatória. O CPF como chave faria a rede guardar o seu CPF."
    )
  end

  def call(conn, {:error, :invalid_pix_key}) do
    error(
      conn,
      :unprocessable_entity,
      "Chave PIX inválida: use e-mail, celular ou chave aleatória."
    )
  end

  def call(conn, {:error, :invalid_cnpj}) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: %{cnpj: ["CNPJ inválido"]}})
  end

  def call(conn, {:error, :invalid_name}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{name: ["Escreva o nome da empresa"]}})
  end

  def call(conn, {:error, :cnpj_taken}) do
    error(conn, :conflict, "Este CNPJ já anuncia por outra conta.")
  end

  def call(conn, {:error, :already_advertiser}) do
    error(conn, :conflict, "Esta conta já tem uma empresa cadastrada.")
  end

  def call(conn, {:error, :not_advertiser}) do
    error(conn, :forbidden, "Cadastre a empresa antes de criar uma campanha.")
  end

  def call(conn, {:error, :invalid_campaign}) do
    error(conn, :unprocessable_entity, "Confira as horas por dia e as datas da campanha.")
  end

  def call(conn, {:error, :own_campaign}) do
    error(conn, :forbidden, "Quem anuncia não aprova a própria campanha.")
  end

  def call(conn, {:error, :already_reviewed}) do
    error(conn, :conflict, "Esta campanha já foi analisada.")
  end

  def call(conn, {:error, :minor_live}) do
    error(conn, :forbidden, "Contas de menores de idade não fazem live.")
  end

  def call(conn, {:error, :too_large}) do
    error(conn, :request_entity_too_large, "O arquivo passa do tamanho máximo.")
  end

  def call(conn, {:error, :too_long}) do
    error(conn, :unprocessable_entity, "O vídeo passa da duração máxima.")
  end

  def call(conn, {:error, :invalid_length}) do
    error(conn, :bad_request, "Informe o tamanho do arquivo em Upload-Length.")
  end

  def call(conn, {:error, :upload_not_found}) do
    error(conn, :unprocessable_entity, "O envio não foi encontrado. Envie o arquivo de novo.")
  end

  def call(conn, {:error, :upload_incomplete}) do
    error(conn, :conflict, "O arquivo ainda não terminou de chegar.")
  end

  def call(conn, {:error, :tus_version}) do
    conn
    |> put_resp_header("tus-version", "1.0.0")
    |> error(:precondition_failed, "Use o protocolo tus 1.0.0.")
  end

  def call(conn, {:error, :tus_content_type}) do
    error(conn, :unsupported_media_type, "Mande os bytes como application/offset+octet-stream.")
  end

  def call(conn, {:error, :tus_offset}) do
    error(
      conn,
      :conflict,
      "O Upload-Offset não confere. Pergunte com HEAD quantos bytes chegaram."
    )
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
