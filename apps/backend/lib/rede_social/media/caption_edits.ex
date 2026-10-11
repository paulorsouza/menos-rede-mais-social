defmodule RedeSocial.Media.CaptionEdits do
  @moduledoc """
  Quem publicou corrige a legenda automática. Os tempos ficam como o
  whisper gerou; só o texto de cada trecho muda. Trecho apagado sai da
  legenda (o whisper às vezes inventa fala onde não tem).

  A legenda corrigida vira um arquivo novo, só deste post, ao lado do vídeo.
  O endereço muda, então a borda não serve a versão antiga.
  """

  alias RedeSocial.{Repo, Storage}
  alias RedeSocial.Accounts.Account
  alias RedeSocial.Social.Post

  @max_cue_chars 300

  @doc "Os trechos da legenda do post, com o tempo e o texto."
  def cues(%Post{captions_path: nil}), do: {:error, :no_captions}

  def cues(%Post{captions_path: path}) do
    with key when is_binary(key) <- Storage.key(path) || {:error, :no_captions},
         {:ok, vtt} <- Storage.get(key) do
      {:ok, parse(vtt)}
    end
  end

  @doc "Troca o texto de cada trecho, na ordem. Só quem publicou."
  def update(%Account{id: id}, %Post{author_id: id} = post, texts) when is_list(texts) do
    with {:ok, cues} <- cues(post),
         true <- length(texts) == length(cues) || {:error, :cues_mismatch},
         {:ok, texts} <- clean(texts) do
      vtt =
        cues
        |> Enum.zip(texts)
        |> Enum.reject(fn {_cue, text} -> text == "" end)
        |> Enum.map(fn {cue, text} -> %{cue | text: text} end)
        |> build()

      dir = post.captions_path |> Storage.key() |> Path.dirname()
      key = "#{dir}/legendas-post-#{post.id}-#{System.unique_integer([:positive])}.vtt"

      with :ok <- Storage.put_binary(key, vtt) do
        old = Storage.key(post.captions_path)

        {:ok, post} =
          post |> Ecto.Changeset.change(captions_path: Storage.path(key)) |> Repo.update()

        # A gerada pelo whisper pode ser de outros posts do mesmo vídeo; a
        # corrigida antes era só deste.
        if String.contains?(old, "/legendas-post-#{post.id}-"), do: Storage.delete(old)
        {:ok, post}
      end
    end
  end

  def update(_account, _post, _texts), do: {:error, :not_found}

  defp clean(texts) do
    texts
    |> Enum.reduce_while({:ok, []}, fn
      text, {:ok, acc} when is_binary(text) ->
        # Linha em branco ou "-->" quebrariam o formato do arquivo.
        text =
          text
          |> String.replace("-->", "→")
          |> String.split(~r/\R/, trim: true)
          |> Enum.map_join("\n", &String.trim/1)
          |> String.trim()

        if String.length(text) <= @max_cue_chars,
          do: {:cont, {:ok, [text | acc]}},
          else: {:halt, {:error, :caption_too_long}}

      _text, _acc ->
        {:halt, {:error, :invalid_caption}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  @doc false
  def parse(vtt) do
    vtt
    |> String.replace("\r\n", "\n")
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.flat_map(fn block ->
      lines = String.split(block, "\n")

      case Enum.split_while(lines, &(not String.contains?(&1, "-->"))) do
        {_before, [timing | text]} ->
          [start, finish] = timing |> String.split("-->") |> Enum.map(&String.trim/1)

          [
            %{
              start: start,
              end: finish |> String.split(" ") |> hd(),
              text: text |> Enum.join("\n") |> String.trim()
            }
          ]

        {_no_timing, []} ->
          []
      end
    end)
  end

  defp build(cues) do
    body = Enum.map_join(cues, "\n\n", &"#{&1.start} --> #{&1.end}\n#{&1.text}")
    "WEBVTT\n\n" <> body <> "\n"
  end
end
