defmodule RedeSocial.RegistroTest do
  use RedeSocial.DataCase, async: true

  alias RedeSocial.Registro
  alias RedeSocial.Registro.{Entry, Merkle}

  defp leaves(n), do: for(i <- 0..(n - 1), do: Merkle.leaf_hash("entrada #{i}"))

  describe "Merkle" do
    test "dá a mesma raiz que o verificador em Rust (services/registro)" do
      assert Base.encode16(Merkle.root(leaves(7)), case: :lower) ==
               "ea6dc9e12718639df89c0af5a185c7ec79f30e0d3f054b503531590e2513c6eb"
    end
  end

  describe "append/2" do
    test "acrescenta com o texto exato da folha e em ordem" do
      {:ok, first} = Registro.append("motor", %{versao: "0.1.0", build: "dev"})
      {:ok, second} = Registro.append("motor", %{versao: "0.2.0", build: "dev"})

      assert first.position == 0
      assert second.position == 1
      assert first.data == ~s(motor\n{"build":"dev","versao":"0.1.0"})
      assert first.leaf_hash == Merkle.leaf_hash(first.data)
    end

    test "a mesma versão do motor não é anotada duas vezes" do
      {:ok, %{position: 0}} = Registro.append_if_changed("motor", %{versao: "0.1.0"})
      assert Registro.append_if_changed("motor", %{versao: "0.1.0"}) == {:ok, :same}
      {:ok, %{position: 1}} = Registro.append_if_changed("motor", %{versao: "0.2.0"})
    end

    test "o banco recusa mudar ou apagar uma entrada" do
      {:ok, entry} = Registro.append("motor", %{versao: "0.1.0"})

      assert_raise Postgrex.Error, ~r/só aceita acréscimos/, fn ->
        entry |> Ecto.Changeset.change(data: "outra coisa") |> Repo.update!()
      end

      assert_raise Postgrex.Error, ~r/só aceita acréscimos/, fn -> Repo.delete_all(Entry) end
    end
  end

  describe "cabeçalho e provas" do
    setup do
      for i <- 0..9, do: {:ok, _} = Registro.append("teste", %{n: i})
      :ok
    end

    test "o cabeçalho é assinado com a chave do registro" do
      head = Registro.head()

      assert head.size == 10

      assert :crypto.verify(:eddsa, :none, Registro.signed_message(head), head.signature, [
               head.public_key,
               :ed25519
             ])
    end

    test "as provas usam as mesmas folhas publicadas" do
      {:ok, inclusion} = Registro.inclusion(3, nil)
      {:ok, consistency} = Registro.consistency(6, nil)

      assert inclusion.size == 10
      assert length(inclusion.proof) == 4

      assert consistency.old_root ==
               Registro.entries(0, 6) |> Enum.map(& &1.leaf_hash) |> Merkle.root()

      assert Registro.inclusion(10, nil) == {:error, :not_found}
    end
  end
end
