defmodule RedeSocial.AccessLogs.AccessLog do
  @moduledoc "Um acesso: a conta, o momento e o IP selado."
  use Ecto.Schema

  schema "access_logs" do
    field :account_id, :binary_id
    field :sealed, :binary, redact: true
    field :inserted_at, :utc_datetime
  end
end
