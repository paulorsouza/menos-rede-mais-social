defmodule RedeSocial.Storage.Local do
  @moduledoc """
  Armazenamento numa pasta local, servida pelo próprio backend em /media.
  Serve para desenvolver sem Docker e para os testes.
  """
  @behaviour RedeSocial.Storage

  @impl true
  def put_file(key, path, _content_type) do
    target = target(key)
    File.mkdir_p!(Path.dirname(target))
    File.cp(path, target)
  end

  @impl true
  def put_binary(key, binary, _content_type) do
    target = target(key)
    File.mkdir_p!(Path.dirname(target))
    File.write(target, binary)
  end

  @impl true
  def list(prefix) do
    keys =
      root()
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, root()))
      |> Enum.filter(&String.starts_with?(&1, prefix))

    {:ok, keys}
  end

  @impl true
  def delete(key) do
    case File.rm(target(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  def root do
    Application.get_env(:rede_social, RedeSocial.Storage, [])
    |> Keyword.get(:root, "priv/media")
  end

  # A chave nunca sobe de pasta: quem monta as chaves é o próprio backend, mas
  # a conferência fica aqui para não depender disso.
  defp target(key) do
    if key |> Path.split() |> Enum.any?(&(&1 in ["..", "."])) do
      raise ArgumentError, "chave inválida: #{inspect(key)}"
    end

    Path.join(root(), key)
  end
end
