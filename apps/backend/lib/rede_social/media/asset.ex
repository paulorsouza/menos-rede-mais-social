defmodule RedeSocial.Media.Asset do
  @moduledoc """
  Um vídeo enviado e o que ele custou para virar HLS: os degraus de
  qualidade, os bytes guardados e o tempo de CPU da conversão.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "media_assets" do
    belongs_to :account, RedeSocial.Accounts.Account
    field :kind, Ecto.Enum, values: [:video, :recording]
    field :status, Ecto.Enum, values: [:processing, :ready, :failed]
    # Arquivo original na pasta de trabalho, até a conversão terminar.
    field :source_path, :string
    field :source_bytes, :integer
    field :width, :integer
    field :height, :integer
    field :duration_ms, :integer
    field :has_audio, :boolean, default: false
    # [%{"short_side" => 360, "video_kbps" => 800, "audio_kbps" => 96, "bytes" => ...}]
    field :renditions, {:array, :map}
    field :stored_bytes, :integer
    field :cpu_ms, :integer
    field :wall_ms, :integer
    field :captions, :boolean, default: false
    field :error, :string
    timestamps(type: :utc_datetime)
  end

  @doc "Onde os arquivos do vídeo ficam no armazenamento."
  def prefix(%__MODULE__{id: id}), do: "v/" <> id
end
