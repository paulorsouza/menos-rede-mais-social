defmodule RedeSocial.MediaFixtures do
  @moduledoc """
  Arquivos de verdade para os testes de mídia, gerados com o ffmpeg. Cada
  arquivo é gerado uma vez por rodada de testes e copiado para cada teste,
  porque o processamento apaga o original.
  """

  @dir "tmp/test_fixtures"

  @doc "Vídeo em pé de 2 segundos (360x640), com som."
  def vertical_video do
    fixture(
      "em-pe.mp4",
      ~w(-f lavfi -i testsrc2=s=360x640:d=2 -f lavfi -i sine=f=440:d=2 -shortest) ++
        ~w(-c:v libx264 -preset ultrafast -c:a aac)
    )
    |> copy()
  end

  @doc "Vídeo deitado de 2 segundos (640x360), sem som."
  def landscape_video do
    fixture("deitado.mp4", ~w(-f lavfi -i testsrc2=s=640x360:d=2 -c:v libx264 -preset ultrafast))
    |> copy()
  end

  @doc """
  Foto JPEG de 3000x1000 com um bloco EXIF que carrega um texto marcado. A
  foto processada não pode ter esse texto.
  """
  def photo_with_exif do
    path = fixture("foto.jpg", ~w(-f lavfi -i testsrc2=s=3000x1000:d=1 -frames:v 1))
    marked = Path.join(@dir, "foto-exif.jpg")

    unless File.exists?(marked) do
      <<0xFF, 0xD8, rest::binary>> = File.read!(path)
      payload = <<"Exif", 0, 0>> <> exif_marker() <> :binary.copy(<<0>>, 16)
      app1 = <<0xFF, 0xE1, byte_size(payload) + 2::16>> <> payload
      publish(marked, &File.write!(&1, <<0xFF, 0xD8>> <> app1 <> rest))
    end

    copy(marked)
  end

  def exif_marker, do: "GPS-LOCALIZACAO-DE-TESTE"

  def upload(path), do: %Plug.Upload{path: path, filename: Path.basename(path)}

  defp fixture(name, args) do
    path = Path.join(@dir, name)

    unless File.exists?(path) do
      File.mkdir_p!(@dir)
      format = if String.ends_with?(name, ".jpg"), do: "image2", else: "mp4"

      publish(path, fn tmp ->
        {_, 0} =
          System.cmd("ffmpeg", ["-y", "-loglevel", "error" | args] ++ ["-f", format, tmp])
      end)
    end

    path
  end

  # Os testes rodam ao mesmo tempo: cada um gera num nome próprio e troca
  # de nome no fim, para ninguém ler um arquivo pela metade.
  defp publish(path, write) do
    tmp = "#{path}.#{System.unique_integer([:positive])}"
    write.(tmp)
    File.rename!(tmp, path)
  end

  defp copy(path) do
    target =
      Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{Path.basename(path)}")

    File.cp!(path, target)
    target
  end
end
