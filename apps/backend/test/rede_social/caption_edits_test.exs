defmodule RedeSocial.CaptionEditsTest do
  use RedeSocial.DataCase, async: true

  import RedeSocial.Fixtures

  alias RedeSocial.{Repo, Storage}
  alias RedeSocial.Media.CaptionEdits
  alias RedeSocial.Social.Post

  @vtt """
  WEBVTT

  00:00:00.000 --> 00:00:02.500
  Um apito no campo.

  00:00:02.500 --> 00:00:04.000
  Obrigado por assistir.
  """

  setup do
    author = account_fixture()
    dir = "v/legenda-#{System.unique_integer([:positive])}"
    :ok = Storage.put_binary(dir <> "/legendas.vtt", @vtt)

    post =
      author
      |> video_fixture()
      |> Ecto.Changeset.change(captions_path: Storage.path(dir <> "/legendas.vtt"))
      |> Repo.update!()

    %{author: author, post: post}
  end

  test "lê os trechos com o tempo e o texto", %{post: post} do
    assert {:ok, [first, second]} = CaptionEdits.cues(post)
    assert first == %{start: "00:00:00.000", end: "00:00:02.500", text: "Um apito no campo."}
    assert second.text == "Obrigado por assistir."
  end

  test "quem publicou corrige o texto, e trecho apagado sai", %{author: author, post: post} do
    {:ok, updated} = CaptionEdits.update(author, post, ["Um apito no  campo! --> gol", ""])

    assert updated.captions_path != post.captions_path
    assert {:ok, [cue]} = CaptionEdits.cues(updated)
    assert cue.start == "00:00:00.000"
    assert cue.text == "Um apito no  campo! → gol"

    # A gerada pelo whisper continua lá para os outros posts do mesmo vídeo.
    assert {:ok, _} = Storage.get(Storage.key(post.captions_path))

    # Corrigir de novo troca o arquivo corrigido, sem deixar o anterior.
    {:ok, again} = CaptionEdits.update(author, Repo.reload!(updated), ["Gol!"])
    assert Storage.get(Storage.key(updated.captions_path)) == {:error, :enoent}
    assert {:ok, [%{text: "Gol!"}]} = CaptionEdits.cues(again)
  end

  test "outra pessoa não corrige, e o número de trechos tem que bater", c do
    assert CaptionEdits.update(account_fixture(), c.post, ["x", "y"]) == {:error, :not_found}
    assert CaptionEdits.update(c.author, c.post, ["só um"]) == {:error, :cues_mismatch}

    long = String.duplicate("a", 301)
    assert CaptionEdits.update(c.author, c.post, [long, "y"]) == {:error, :caption_too_long}
    assert Repo.get!(Post, c.post.id).captions_path == c.post.captions_path
  end
end
