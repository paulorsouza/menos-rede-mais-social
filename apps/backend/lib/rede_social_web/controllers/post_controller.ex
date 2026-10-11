defmodule RedeSocialWeb.PostController do
  use RedeSocialWeb, :controller

  alias RedeSocial.{Moderation, Social}
  alias RedeSocial.Media.CaptionEdits
  alias RedeSocial.Social.Post
  alias RedeSocialWeb.Present

  action_fallback RedeSocialWeb.FallbackController

  @doc """
  Publica. A mídia vem de um envio já completo (`upload_id`, o caminho do
  app) ou de um arquivo no próprio formulário (`media`, só fotos pequenas).
  """
  def create(conn, params) do
    attrs = Map.take(params, ~w(kind body alt_text monetized ad_markers))

    media =
      case params do
        %{"upload_id" => id} when is_binary(id) -> {:upload, id}
        %{"media" => %Plug.Upload{} = upload} -> upload
        _ -> nil
      end

    with {:ok, post} <- Social.create_post(conn.assigns.current_account, attrs, media) do
      conn
      |> put_status(:created)
      |> json(%{post: Present.post(post)})
    end
  end

  def show(conn, %{"id" => id}) do
    with %{} = post <- find(conn, id) do
      stats = Social.stats([post], conn.assigns.current_account) |> Map.fetch!(post.id)
      json(conn, %{post: Present.post(post, stats)})
    end
  end

  def like(conn, %{"id" => id}) do
    with %{} = post <- find(conn, id),
         {:ok, liked} <- Social.toggle_like(conn.assigns.current_account, post) do
      json(conn, reaction(conn, post, :liked, liked))
    end
  end

  def save(conn, %{"id" => id}) do
    with %{} = post <- find(conn, id),
         {:ok, saved} <- Social.toggle_save(conn.assigns.current_account, post) do
      json(conn, reaction(conn, post, :saved, saved))
    end
  end

  def view(conn, %{"id" => id} = params) do
    with %{} = post <- find(conn, id) do
      watched_ms = parse_integer(params["watched_ms"])
      :ok = Social.record_view(conn.assigns.current_account, post, watched_ms)
      send_resp(conn, :no_content, "")
    end
  end

  @doc "Os trechos da legenda, para quem publicou corrigir."
  def captions(conn, %{"id" => id}) do
    with %Post{} = post <- own_post(conn, id),
         {:ok, cues} <- CaptionEdits.cues(post) do
      json(conn, %{cues: cues})
    end
  end

  def update_captions(conn, %{"id" => id, "texts" => texts}) do
    with %Post{} = post <- own_post(conn, id),
         {:ok, post} <- CaptionEdits.update(conn.assigns.current_account, post, texts),
         {:ok, cues} <- CaptionEdits.cues(post) do
      json(conn, %{cues: cues, captions_url: RedeSocial.Storage.url(post.captions_path)})
    end
  end

  def update_captions(_conn, _params), do: {:error, :invalid_caption}

  defp own_post(conn, id) do
    author = conn.assigns.current_account

    case find(conn, id) do
      %Post{author_id: author_id} = post when author_id == author.id -> post
      _ -> {:error, :not_found}
    end
  end

  @doc "Denunciar um post citando uma regra."
  def report(conn, %{"id" => id} = params) do
    with %{} = post <- find(conn, id),
         :ok <-
           Moderation.report(conn.assigns.current_account, post, parse_integer(params["rule"])) do
      json(conn, %{ok: true})
    end
  end

  @doc "O autor recorre da remoção do próprio post."
  def appeal(conn, %{"id" => id} = params) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %{} = post <- Social.get_post_any(id),
         {:ok, _appeal} <- Moderation.appeal(conn.assigns.current_account, post, params["text"]) do
      conn |> put_status(:created) |> json(%{ok: true})
    else
      :error -> {:error, :not_found}
      other -> other
    end
  end

  defp find(conn, id) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> Social.get_post(id, conn.assigns.current_account)
      _ -> nil
    end
  end

  defp reaction(conn, post, key, value) do
    stats = Social.stats([post], conn.assigns.current_account) |> Map.fetch!(post.id)
    %{key => value, likes: stats.likes, saves: stats.saves}
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      :error -> 0
    end
  end

  defp parse_integer(_value), do: 0
end
