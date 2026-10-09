defmodule RedeSocial.IdentificationTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{AccessLogs, Accounts, Identification, Repo}
  alias RedeSocial.Accounts.CPF
  alias RedeSocial.AccessLogs.AccessLog
  alias RedeSocial.Vault.Fake

  defp officer do
    {:ok, officer} = Identification.grant_legal_officer(account_fixture())
    officer
  end

  # As partes de um guardião para todos os itens da ordem, como sairiam do
  # `cofre parcial`.
  defp give(order, guardian) do
    partials =
      Map.new(Identification.items(order), fn item ->
        {:ok, partial} = Fake.demo_partial(guardian, item.sealed)
        {item.key, partial}
      end)

    Identification.submit(order, guardian, partials)
  end

  describe "cadastro" do
    test "o CPF só fica selado, amarrado ao id da conta" do
      cpf = CPF.generate_for_testing()

      {:ok, account} =
        Accounts.register_verified(
          %{nickname: "pessoa.selada", govbr_level: :prata, age_band: :adult},
          cpf
        )

      assert account.cpf_ciphertext == "fake|cpf:#{account.id}|#{cpf}"
      refute account.cpf_fingerprint == cpf
    end
  end

  describe "registros de acesso" do
    test "no máximo um por hora, com o IP selado" do
      account = account_fixture()

      :ok = AccessLogs.record(account, {200, 160, 1, 10})
      :ok = AccessLogs.record(account, {200, 160, 1, 99})

      assert [log] = AccessLogs.for_account(account.id)
      assert log.sealed == "fake|#{AccessLogs.context(account.id, log.inserted_at)}|200.160.1.10"
    end

    test "somem depois de seis meses" do
      account = account_fixture()
      old = DateTime.add(DateTime.utc_now(), -200 * 86_400, :second) |> DateTime.truncate(:second)
      Repo.insert!(%AccessLog{account_id: account.id, sealed: "x", inserted_at: old})
      :ok = AccessLogs.record(account, "10.0.0.1")

      assert AccessLogs.purge() == 1
      assert [_recent] = AccessLogs.for_account(account.id)
    end
  end

  describe "ordem judicial" do
    setup do
      target = account_fixture()
      :ok = AccessLogs.record(target, "177.10.20.30")
      %{target: target, officer: officer()}
    end

    test "só o setor jurídico registra, e só para conta com CPF", %{
      target: target,
      officer: officer
    } do
      attrs = %{"court" => "1ª Vara Criminal de Campinas", "case_number" => "0001234-56.2026"}

      assert Identification.create_order(account_fixture(), target.nickname, attrs) ==
               {:error, :not_legal_officer}

      {:ok, basic} = Accounts.register_basic(%{nickname: "so.le"})

      assert Identification.create_order(officer, basic.nickname, attrs) ==
               {:error, :no_sealed_cpf}

      assert {:ok, _order} = Identification.create_order(officer, target.nickname, attrs)
    end

    test "o pedido leva o CPF e os acessos, todos selados", %{target: target, officer: officer} do
      {:ok, order} = Identification.create_order(officer, target.nickname, %{"court" => "Juízo"})

      assert %{items: [%{key: "cpf"}, %{key: "acesso-" <> _}]} = Identification.package(order)
    end

    test "dois guardiões não bastam; três abrem uma vez só", %{target: target, officer: officer} do
      {:ok, order} =
        Identification.create_order(officer, target.nickname, %{
          "court" => "2ª Vara Cível do Recife"
        })

      {:ok, order} = give(order, 1)
      {:ok, order} = give(order, 4)
      assert Identification.ready_guardians(order) == [1, 4]
      assert Identification.open(officer, order) == {:error, :not_enough_guardians}

      {:ok, order} = give(order, 5)
      assert {:ok, result} = Identification.open(officer, order)

      [_, digits] = String.split(target.cpf_ciphertext, "|", parts: 3) |> Enum.drop(1)
      assert result.cpf == CPF.format(digits)
      assert [%{ip: "177.10.20.30"}] = result.accesses

      order = Identification.get_order(order.id)
      assert order.status == "opened"
      assert Identification.open(officer, order) == {:error, :already_opened}
    end

    test "parte de um guardião que diz ser outro é recusada", %{target: target, officer: officer} do
      {:ok, order} = Identification.create_order(officer, target.nickname, %{"court" => "Juízo"})
      {:ok, partial} = Fake.demo_partial(2, "x")
      partials = Map.new(Identification.items(order), &{&1.key, partial})

      assert Identification.submit(order, 3, partials) == {:error, {:bad_partial, "cpf"}}
    end

    test "o registro público mostra o juízo e nunca quem foi identificado", context do
      %{target: target, officer: officer} = context
      secret_target = account_fixture()

      for {account, attrs} <- [
            {target, %{"court" => "3ª Vara Federal", "case_number" => "5000001-00.2026"}},
            {secret_target, %{"court" => "Vara da Infância", "secret_case" => true}}
          ] do
        {:ok, order} = Identification.create_order(officer, account.nickname, attrs)
        {:ok, order} = give(order, 1)
        {:ok, order} = give(order, 2)
        {:ok, order} = give(order, 3)
        {:ok, _result} = Identification.open(officer, order)
      end

      log = Identification.public_log()
      assert %{requested: 2, opened: 2, secret: 1} = log
      assert [%{court: "3ª Vara Federal", case_number: "5000001-00.2026"}] = log.entries

      text = inspect(log)
      refute text =~ target.nickname
      refute text =~ secret_target.nickname
    end
  end
end
