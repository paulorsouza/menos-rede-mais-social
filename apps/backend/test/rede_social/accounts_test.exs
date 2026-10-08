defmodule RedeSocial.AccountsTest do
  use RedeSocial.DataCase, async: true

  alias RedeSocial.Accounts

  @cpf "123.456.789-09"

  describe "register_verified/2" do
    test "cria a conta com selo e sem guardar o CPF em texto" do
      {:ok, account} =
        Accounts.register_verified(
          %{nickname: "Maria.Silva", govbr_level: :prata, age_band: :adult},
          @cpf
        )

      assert account.nickname == "maria.silva"
      assert Accounts.verified?(account)
      assert Accounts.can_monetize?(account)
      assert byte_size(account.cpf_fingerprint) == 32
      refute String.contains?(account.cpf_fingerprint, "12345678909")
    end

    test "não deixa a mesma pessoa ter duas contas" do
      attrs = %{govbr_level: :bronze, age_band: :adult}
      {:ok, _first} = Accounts.register_verified(Map.put(attrs, :nickname, "primeira"), @cpf)

      {:error, changeset} =
        Accounts.register_verified(Map.put(attrs, :nickname, "segunda"), "12345678909")

      assert "já existe uma conta para esta pessoa" in errors_on(changeset).cpf_fingerprint
    end

    test "recusa CPF inválido" do
      attrs = %{nickname: "alguem", govbr_level: :ouro, age_band: :adult}
      assert Accounts.register_verified(attrs, "123.456.789-00") == {:error, :invalid_cpf}
    end

    test "conta bronze tem selo, mas não recebe por anúncios" do
      {:ok, account} =
        Accounts.register_verified(
          %{nickname: "bronze", govbr_level: :bronze, age_band: :adult},
          @cpf
        )

      assert Accounts.verified?(account)
      refute Accounts.can_monetize?(account)
    end
  end

  describe "register_basic/1" do
    test "cria conta sem selo e sem monetização" do
      {:ok, account} = Accounts.register_basic(%{nickname: "visitante_1"})

      refute Accounts.verified?(account)
      refute Accounts.can_monetize?(account)
      assert is_nil(account.cpf_fingerprint)
    end

    test "valida o formato do apelido" do
      for nickname <- ["ab", "zé", "com espaço", String.duplicate("a", 31)] do
        {:error, changeset} = Accounts.register_basic(%{nickname: nickname})
        assert errors_on(changeset).nickname != []
      end
    end

    test "não aceita apelido repetido, nem com letras maiúsculas" do
      {:ok, _account} = Accounts.register_basic(%{nickname: "joao"})
      {:error, changeset} = Accounts.register_basic(%{nickname: "JOAO"})

      assert "este apelido já está em uso" in errors_on(changeset).nickname
    end
  end
end
