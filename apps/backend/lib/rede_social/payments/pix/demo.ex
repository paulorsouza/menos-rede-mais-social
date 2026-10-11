defmodule RedeSocial.Payments.Pix.Demo do
  @moduledoc """
  Banco simulado, só para a demonstração e os testes. O diretório de chaves
  é uma tabela com as chaves das pessoas de exemplo, a transferência sempre
  chega, e a cobrança é paga pelo botão "Simular pagamento".
  """
  @behaviour RedeSocial.Payments.Pix

  alias RedeSocial.Payments.{BRCode, DemoDirectory}
  alias RedeSocial.Repo

  @receiver_key "pix@rede-social.demo"

  @impl true
  def lookup_key(key) do
    case Repo.get(DemoDirectory, key) do
      %DemoDirectory{document: document, name: name} ->
        {:ok, %{document: document, name: name}}

      # Chave do tipo CNPJ é sempre do próprio CNPJ.
      nil ->
        case RedeSocial.Accounts.CNPJ.normalize(key) do
          {:ok, cnpj} when cnpj == key -> {:ok, %{document: cnpj, name: "Empresa"}}
          _ -> {:error, :not_found}
        end
    end
  end

  @impl true
  def transfer(_key, cents, _idempotency_id) when cents > 0, do: {:ok, e2e_id("E")}

  @impl true
  def refund(_txid, cents, _idempotency_id) when cents > 0, do: {:ok, e2e_id("D")}

  # Formato do id fim a fim do PIX: letra + ISPB do banco + data e hora +
  # sequência. A devolução começa com D.
  defp e2e_id(letter) do
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M")
    sequence = :crypto.strong_rand_bytes(5) |> Base.encode32(padding: false) |> binary_part(0, 7)
    letter <> "00000000" <> stamp <> "DEMO" <> sequence
  end

  @impl true
  def create_charge(cents, txid, _description) do
    {:ok, BRCode.build(@receiver_key, cents, txid, "REDE SOCIAL DEMO", "BRASILIA")}
  end

  @doc "Põe uma chave no diretório simulado (os dados de demonstração fazem isso)."
  def register(key, document, name) do
    Repo.insert!(%DemoDirectory{key: key, document: document, name: name},
      on_conflict: :replace_all,
      conflict_target: :key
    )
  end
end
