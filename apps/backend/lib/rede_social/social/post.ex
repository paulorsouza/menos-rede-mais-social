defmodule RedeSocial.Social.Post do
  @moduledoc """
  Um post. Pode ser texto curto (até 140 caracteres e sem respostas), foto,
  vídeo, short ou live. A live, quando acaba, vira vídeo ou short com a
  gravação.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias RedeSocial.Accounts.Account

  @kinds [:text, :photo, :video, :short, :live]
  @ad_markers ~w(start middle end)
  @text_limit 140

  schema "posts" do
    belongs_to :author, Account, type: :binary_id

    field :kind, Ecto.Enum, values: @kinds
    field :body, :string
    # Endereço público da foto, ou da lista HLS do vídeo (master.m3u8).
    field :media_path, :string

    # Vídeo nasce "processando" e só aparece para os outros quando a fila
    # termina de converter. Foto e texto já nascem prontos.
    field :media_status, Ecto.Enum, values: [:ready, :processing, :failed], default: :ready
    belongs_to :media_asset, RedeSocial.Media.Asset, type: :binary_id
    field :poster_path, :string
    field :captions_path, :string
    field :duration_ms, :integer
    field :width, :integer
    field :height, :integer

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

      :live ->
        changeset
        |> put_change(:alt_text, nil)
        |> validate_length(:body, max: 500)
        |> put_change(:monetized, false)
        |> put_change(:ad_markers, [])

      kind when kind in [:photo, :video, :short] ->
        changeset
        |> then(&if(kind == :photo, do: &1, else: put_change(&1, :alt_text, nil)))
        |> validate_media()
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

  # Vídeo processando ainda não tem endereço, mas já tem o asset na fila.
  defp validate_media(changeset) do
    if get_field(changeset, :media_status) == :processing and
         get_field(changeset, :media_asset_id),
       do: changeset,
       else: validate_required(changeset, [:media_path], message: "envie o arquivo")
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
