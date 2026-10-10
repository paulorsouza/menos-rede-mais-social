defmodule RedeSocialWeb.RegistroController do
  @moduledoc """
  O registro público, aberto para qualquer pessoa, sem login. Os hashes vão
  em hexadecimal e a assinatura e a chave em base64.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.Registro

  action_fallback RedeSocialWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{head: head(Registro.head()), entries: Enum.map(Registro.latest(50), &entry/1)})
  end

  def entries(conn, params) do
    from = integer(params["de"], 0)
    to = integer(params["ate"], nil)
    json(conn, %{entries: Enum.map(Registro.entries(from, to), &entry/1)})
  end

  def inclusion(conn, %{"index" => index} = params) do
    with {:ok, proof} <- Registro.inclusion(integer(index, -1), integer(params["tamanho"], nil)) do
      json(conn, %{
        index: proof.index,
        size: proof.size,
        leaf_hash: hex(proof.leaf_hash),
        root: hex(proof.root),
        proof: Enum.map(proof.proof, &hex/1)
      })
    end
  end

  def consistency(conn, params) do
    with {:ok, proof} <-
           Registro.consistency(integer(params["de"], 0), integer(params["para"], nil)) do
      json(conn, %{
        from: proof.from,
        to: proof.to,
        old_root: hex(proof.old_root),
        new_root: hex(proof.new_root),
        proof: Enum.map(proof.proof, &hex/1)
      })
    end
  end

  defp head(head) do
    %{
      size: head.size,
      root: hex(head.root),
      timestamp: head.timestamp,
      signature: Base.encode64(head.signature),
      public_key: Base.encode64(head.public_key)
    }
  end

  defp entry(entry) do
    %{
      index: entry.position,
      kind: entry.kind,
      data: entry.data,
      leaf_hash: hex(entry.leaf_hash),
      at: entry.inserted_at
    }
  end

  defp hex(binary), do: Base.encode16(binary, case: :lower)

  defp integer(nil, default), do: default

  defp integer(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} -> number
      _ -> default
    end
  end
end
