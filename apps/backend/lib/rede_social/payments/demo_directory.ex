defmodule RedeSocial.Payments.DemoDirectory do
  @moduledoc "Só na demonstração: o diretório de chaves PIX do banco simulado."
  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "demo_pix_directory" do
    field :document, :string, redact: true
    field :name, :string
  end
end
