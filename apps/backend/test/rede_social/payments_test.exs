defmodule RedeSocial.PaymentsTest do
  use RedeSocial.DataCase, async: true
  use Oban.Testing, repo: RedeSocial.Repo

  import RedeSocial.Fixtures

  alias RedeSocial.{Accounts, EngineStub, Payments, Repo}
  alias RedeSocial.Accounts.CPF
  alias RedeSocial.Ads.{AdView, Impression}
  alias RedeSocial.Payments.{Payout, Pix, TransferWorker}
  alias RedeSocial.Registro.{Entry, Merkle}

  defp account_with_cpf(attrs \\ %{}) do
    cpf = CPF.generate_for_testing()
    nickname = "criador#{System.unique_integer([:positive])}"

    {:ok, account} =
      Accounts.register_verified(
        Map.merge(%{nickname: nickname, govbr_level: :prata, age_band: :adult}, attrs),
        cpf
      )

    {account, cpf}
  end

  describe "chave PIX" do
    test "vale a chave que o banco diz ser do próprio CPF" do
      {account, cpf} = account_with_cpf()
      Pix.Demo.register("maria@pix.demo", cpf, "Maria")

      {:ok, key} = Payments.register_pix_key(account, " Maria@PIX.demo ")
      assert key.key == "maria@pix.demo"
      assert key.hint == "m***@pix.demo"
    end

    test "chave de outra pessoa, chave que não existe e CPF como chave não valem" do
      {account, _cpf} = account_with_cpf()
      {_other, other_cpf} = account_with_cpf()
      Pix.Demo.register("outra@pix.demo", other_cpf, "Outra")

      assert Payments.register_pix_key(account, "outra@pix.demo") == {:error, :pix_key_not_yours}

      assert Payments.register_pix_key(account, "ninguem@pix.demo") ==
               {:error, :pix_key_not_found}

      assert Payments.register_pix_key(account, CPF.format(other_cpf)) == {:error, :cpf_pix_key}
    end

    test "celular vira o formato do PIX" do
      assert Payments.normalize_key("(11) 98765-4321") == {:ok, :phone, "+5511987654321"}
      assert Payments.normalize_key("+55 11 98765-4321") == {:ok, :phone, "+5511987654321"}
    end
  end

  describe "fechamento do mês" do
    setup do
      EngineStub.stub()
      last_month = Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: -1)
      during = DateTime.new!(Date.add(last_month, 10), ~T[15:00:00], "Etc/UTC")

      {paid, cpf} = account_with_cpf()
      Pix.Demo.register("pago@pix.demo", cpf, "Pago")
      {:ok, _} = Payments.register_pix_key(paid, "pago@pix.demo")

      {small, _} = account_with_cpf()
      {keyless, keyless_cpf} = account_with_cpf()
      campaign = campaign_fixture()

      add_views = fn creator, count, verified ->
        video = video_fixture(creator)

        for _ <- 1..count do
          Repo.insert!(%AdView{
            campaign_id: campaign.id,
            post_id: video.id,
            creator_id: creator.id,
            viewer_id: account_fixture().id,
            viewer_verified: verified,
            regional: false,
            moment: "start",
            revenue_cents: 3,
            inserted_at: during
          })
        end
      end

      add_views.(paid, 600, true)
      add_views.(paid, 2, false)
      # 50 views valem R$ 0,55: abaixo do mínimo de R$ 1,00.
      add_views.(small, 50, true)
      add_views.(keyless, 600, true)

      Repo.insert!(%Impression{
        campaign_id: campaign.id,
        revenue_cents: 10,
        splits: %{paid.id => 7},
        breakdown: [
          %{"post_id" => 1, "author_id" => paid.id, "watched_ms" => 5000, "monetized" => true}
        ],
        inserted_at: during
      })

      %{
        last_month: last_month,
        paid: paid,
        small: small,
        keyless: keyless,
        keyless_cpf: keyless_cpf
      }
    end

    test "fecha cada criador, publica a raiz e manda os repasses", c do
      {:ok, month, payouts} = Payments.close_month(c.last_month)
      by_account = Map.new(payouts, &{&1.account_id, &1})

      # 600 views contam (as 2 de conta básica, não), mais 55% do anúncio dos shorts.
      assert by_account[c.paid.id].total_cents == 660 + 5
      assert by_account[c.paid.id].status == :sending
      assert by_account[c.small.id].status == :carried
      assert by_account[c.keyless.id].status == :no_key

      entry = Repo.get_by!(Entry, position: month.registro_position)
      assert entry.kind == "fechamento"
      assert entry.data =~ Base.encode16(month.root, case: :lower)
      assert month.revenue_cents == (600 + 2 + 50 + 600) * 3 + 10

      assert_enqueued(worker: TransferWorker, args: %{payout_id: by_account[c.paid.id].id})
      :ok = perform_job(TransferWorker, %{payout_id: by_account[c.paid.id].id})

      paid = Repo.get!(Payout, by_account[c.paid.id].id)
      assert paid.status == :paid
      assert paid.pix_e2e_id =~ ~r/^E\d{8}\d{12}/
      assert paid.pix_key_hint == "p***@pix.demo"

      assert Payments.close_month(c.last_month) == {:error, :already_closed}
    end

    test "o extrato leva a prova de cada linha na árvore publicada", c do
      {:ok, month, _payouts} = Payments.close_month(c.last_month)
      statement = Payments.statement(c.paid, Calendar.strftime(c.last_month, "%Y-%m"))
      file = Payments.statement_file(statement)

      hashes =
        Repo.all(
          from l in RedeSocial.Payments.Leaf,
            where: l.month_id == ^month.id,
            order_by: [asc: l.position],
            select: l.leaf_hash
        )

      assert file.fechamento.raiz == Base.encode16(Merkle.root(hashes), case: :lower)
      assert length(file.provas) == length(statement.payout.result["leaves"])

      for {text, proof} <- Enum.zip(statement.payout.result["leaves"], file.provas) do
        assert Enum.at(hashes, proof.folha) == Merkle.leaf_hash(text)

        assert proof.caminho ==
                 Enum.map(
                   Merkle.inclusion_proof(hashes, proof.folha),
                   &Base.encode16(&1, case: :lower)
                 )
      end

      # Quem viu aparece só pelo pseudônimo do mês.
      viewers = Enum.map(file.entrada["video_views"], & &1["viewer"])
      assert Enum.all?(viewers, &(&1 =~ ~r/^[0-9a-f]{32}$/))
    end

    test "o saldo pequeno vai para o mês seguinte", c do
      {:ok, _month, _payouts} = Payments.close_month(c.last_month)
      {:ok, _month, payouts} = Payments.close_month(Date.utc_today())

      carried = Enum.find(payouts, &(&1.account_id == c.small.id))
      assert carried.input["carry_in_cents"] == 55
      assert carried.total_cents == 55
      assert carried.status == :carried
    end

    test "quem cadastra a chave depois recebe o que estava esperando", c do
      {:ok, _month, payouts} = Payments.close_month(c.last_month)
      waiting = Enum.find(payouts, &(&1.account_id == c.keyless.id))
      assert waiting.status == :no_key

      Pix.Demo.register("atrasada@pix.demo", c.keyless_cpf, "Atrasada")
      {:ok, _} = Payments.register_pix_key(c.keyless, "atrasada@pix.demo")

      assert Repo.get!(Payout, waiting.id).status == :sending
      assert_enqueued(worker: TransferWorker, args: %{payout_id: waiting.id})
    end
  end

  describe "contas abertas" do
    test "cada mês fechado mostra receita, criadores e fundo" do
      EngineStub.stub()
      {:ok, _month, _payouts} = Payments.close_month(Date.utc_today())

      assert [%{revenue_cents: 0, creators_cents: 0, fund_cents: 0, root: root}] =
               Payments.open_accounts()

      assert root =~ ~r/^[0-9a-f]{64}$/
    end
  end
end
