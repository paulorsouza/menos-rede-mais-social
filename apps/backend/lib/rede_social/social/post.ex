defmodule RedeSocial.Social.Post do
  @moduledoc """
  Um post. Pode ser texto curto (até 140 caracteres e sem respostas), foto,
  vídeo ou short.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias RedeSocial.Accounts.Account

  @kinds [:text, :photo, :video, :short]
  @ad_markers ~w(start middle end)
  @text_limit 140

  schema "posts" do
    belongs_to :author, Account, type: :binary_id

    field :kind, Ecto.Enum, values: @kinds
    field :body, :string
    field :media_path, :string

    # Descrição da foto para quem usa leitor de tela. Só faz sentido em foto.
    field :alt_text, :string

    # O criador decide se o vídeo tem anúncio e em que momento ele entra.
    field :monetized, :boolean, default: false
    field :ad_markers, {:array, :string}, default: []

    # Remoção pela moderação: quando, por qual regra pública e por quem.
    field :removed_at, :utc_datetime
    field :removal_rule, :integer
    field :removal_reason, :string
    belongs_to :removed_by, Account, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def text_limit, do: @text_limit

  @doc "O autor e a mídia já vêm preenchidos no struct; aqui só entra o que a pessoa escreveu."
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:kind, :body, :alt_text, :monetized, :ad_markers])
    |> validate_required([:kind])
    |> update_change(:body, &String.trim/1)
    |> update_change(:alt_text, &blank_to_nil/1)
    |> validate_length(:alt_text, max: 1000, message: "no máximo 1000 caracteres")
    |> validate_by_kind()
  end

  defp validate_by_kind(changeset) do
    case get_field(changeset, :kind) do
      :text ->
        changeset
        |> put_change(:alt_text, nil)
        |> validate_required([:body], message: "escreva alguma coisa")
        |> validate_length(:body, max: @text_limit, message: "no máximo 140 caracteres")
        |> put_change(:monetized, false)
        |> put_change(:ad_markers, [])

      kind when kind in [:photo, :video, :short] ->
        changeset
        |> then(&if(kind == :photo, do: &1, else: put_change(&1, :alt_text, nil)))
        |> validate_required([:media_path], message: "envie o arquivo")
        |> validate_length(:body, max: 500)
        |> validate_ads(kind)

      _ ->
        changeset
    end
  end

  # Fotos não têm anúncio. Shorts têm anúncio a cada 6, sem marcação.
  # Vídeos têm anúncio só nos pontos que o criador marcar.
  defp validate_ads(changeset, :photo) do
    changeset |> put_change(:monetized, false) |> put_change(:ad_markers, [])
  end

  defp validate_ads(changeset, :short), do: put_change(changeset, :ad_markers, [])

  defp validate_ads(changeset, :video) do
    changeset
    |> validate_subset(:ad_markers, @ad_markers)
    |> then(fn changeset ->
      if get_field(changeset, :ad_markers) == [],
        do: put_change(changeset, :monetized, false),
        else: put_change(changeset, :monetized, true)
    end)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
