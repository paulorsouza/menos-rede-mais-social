defmodule RedeSocial.GraphCommitmentsTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Engine, Feed, GraphCommitments, Registro, Social}
  alias RedeSocial.Registro.Merkle

  # Um retrato que já pega tudo o que o teste criou.
  defp after_now, do: DateTime.add(DateTime.utc_now(), 1)

  describe "Merkle por níveis" do
    test "dá a mesma raiz e as mesmas provas da versão recursiva" do
      for n <- 1..40 do
        leaves = for i <- 0..(n - 1), do: Merkle.leaf_hash("folha #{i}")
        levels = Merkle.levels(leaves)

        assert Merkle.levels_root(levels) == Merkle.root(leaves), "n=#{n}"

        for i <- 0..(n - 1) do
          assert Merkle.levels_proof(levels, i) == Merkle.inclusion_proof(leaves, i),
                 "n=#{n} i=#{i}"
        end
      end
    end
  end

  describe "retrato" do
    test "a raiz vai para o registro e ninguém aparece pelo id" do
      liker = account_fixture()
      post = post_fixture(account_fixture())
      {:ok, true} = Social.toggle_like(liker, post)

      {:ok, snapshot} = GraphCommitments.take_snapshot(after_now())

      assert snapshot.size == 1
      assert %{kind: "raiz-dados", data: data} = Registro.last_of_kind("raiz-dados")
      assert data =~ Base.encode16(snapshot.root, case: :lower)
      refute data =~ liker.id
    end

    test "o pseudônimo muda de um retrato para outro" do
      account = account_fixture()
      {:ok, first} = GraphCommitments.take_snapshot(after_now())
      {:ok, second} = GraphCommitments.take_snapshot(after_now())

      refute GraphCommitments.pseudonym(first, account.id) ==
               GraphCommitments.pseudonym(second, account.id)
    end
  end

  describe "conta do feed" do
    test "traz a prova de cada ligação que estava no retrato" do
      viewer = account_fixture()
      followed = account_fixture()
      post = post_fixture(followed)
      {:ok, true} = Social.toggle_follow(viewer, followed)
      {:ok, true} = Social.toggle_like(viewer, post_fixture(account_fixture()))
      {:ok, snapshot} = GraphCommitments.take_snapshot(after_now())

      # Uma curtida depois do retrato fica marcada como recente.
      {:ok, true} = Social.toggle_like(viewer, post)

      Req.Test.stub(Engine, fn conn ->
        case conn.request_path do
          "/feed/rank" ->
            Req.Test.json(conn, %{
              "items" => [],
              "receipt" => %{"input_sha256" => "x"},
              "engine_version" => "0.1.0",
              "engine_build" => "dev",
              "params_version" => 2,
              "params_sha256" => "abc"
            })

          "/transparency" ->
            Req.Test.json(conn, %{"receipt_public_key" => "chave"})
        end
      end)

      {:ok, account} = Feed.account(viewer, "bubble", [:text])

      assert account.retrato.raiz == Base.encode16(snapshot.root, case: :lower)
      assert [%{seguido: _, folha: _, caminho: _}] = account.provas.seguindo
      assert length(account.provas.ligacoes) == 1
      assert length(account.recentes.ligacoes) == 1

      # Cada prova fecha com a raiz do retrato.
      [proof] = account.provas.ligacoes
      edge = Enum.at(account.entrada.edges, proof.item)
      alias_ = Map.fetch!(account.pseudonimos, edge.user_id)
      leaf = Merkle.leaf_hash(GraphCommitments.like_text(alias_, edge.post_id, edge.at))
      path = Enum.map(proof.caminho, &Base.decode16!(&1, case: :lower))

      assert snapshot
             |> GraphCommitments.proofs([
               GraphCommitments.like_text(alias_, edge.post_id, edge.at)
             ]) ==
               [%{position: proof.folha, proof: path}]

      refute leaf == nil
    end
  end
end
