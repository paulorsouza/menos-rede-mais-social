defmodule RedeSocial.Demo.Clips do
  @moduledoc """
  Gera os vídeos da demonstração com o ffmpeg: um fundo animado com o título
  escrito por cima. Com o espeak-ng instalado, uma voz sintética lê a
  legenda do post, para as legendas automáticas terem o que transcrever.
  Sem ffmpeg instalado, a demo sobe sem vídeos.
  """

  alias RedeSocial.Uploads

  @font "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
  @font_size 40
  @line_height 54

  def available?, do: System.find_executable("ffmpeg") != nil and File.exists?(@font)

  @doc "Gera um vídeo na pasta de trabalho e devolve o caminho dele."
  def render(title, style, seconds, {width, height} \\ {480, 854}, narration \\ nil) do
    File.mkdir_p!(Uploads.staging_dir())
    path = Path.join(Uploads.staging_dir(), "clipe-#{Ecto.UUID.generate()}.mp4")
    voice = narration && speak(narration)

    # A voz é mais curta que o vídeo: o resto é silêncio.
    audio = if voice, do: ["-i", voice, "-af", "apad", "-c:a", "aac"], else: ["-an"]

    args =
      ["-y", "-loglevel", "error", "-f", "lavfi", "-i", source(style, width, height, seconds)] ++
        audio ++
        ["-t", Integer.to_string(seconds), "-vf", text_filter(title)] ++
        ~w(-c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -movflags +faststart) ++
        [path]

    result =
      case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
        {_output, 0} -> {:ok, path}
        {output, _status} -> {:error, output}
      end

    if voice, do: File.rm(voice)
    result
  end

  # A legenda lida em voz alta, num WAV temporário. Sem espeak-ng, sem voz.
  defp speak(text) do
    wav = Path.join(System.tmp_dir!(), "voz-#{Ecto.UUID.generate()}.wav")

    with exe when is_binary(exe) <- System.find_executable("espeak-ng"),
         {_, 0} <-
           System.cmd(exe, ["-v", "pt-br", "-s", "150", "-w", wav, text], stderr_to_stdout: true) do
      wav
    else
      _ -> nil
    end
  end

  defp source(:warm, width, height, seconds),
    do: gradients(width, height, seconds, ~w(0xff7a59 0xffd166 0xef476f))

  defp source(:cool, width, height, seconds),
    do: gradients(width, height, seconds, ~w(0x4cc9f0 0x4361ee 0x7209b7))

  defp source(:green, width, height, seconds),
    do: gradients(width, height, seconds, ~w(0x2a9d8f 0x90be6d 0x264653))

  defp source(:night, width, height, seconds),
    do: gradients(width, height, seconds, ~w(0x14213d 0xfca311 0x3a0ca3))

  defp source(:fractal, width, height, _seconds), do: "mandelbrot=s=#{width}x#{height}:rate=25"

  defp source(:life, width, height, _seconds) do
    "life=s=#{width}x#{height}:mold=10:rate=25:ratio=0.1:death_color=0x1b263b:life_color=0x4cc9f0"
  end

  defp gradients(width, height, seconds, colors) do
    color_options =
      colors |> Enum.with_index() |> Enum.map_join(":", fn {color, i} -> "c#{i}=#{color}" end)

    "gradients=s=#{width}x#{height}:#{color_options}:nb_colors=#{length(colors)}:speed=0.03:d=#{seconds}"
  end

  defp text_filter(title) do
    lines = title |> sanitize() |> wrap(16)
    total = length(lines) * @line_height

    lines
    |> Enum.with_index()
    |> Enum.map_join(",", fn {line, i} ->
      "drawtext=fontfile=#{@font}:text='#{line}':fontcolor=white:fontsize=#{@font_size}" <>
        ":x=(w-text_w)/2:y=(h-#{total})/2+#{i * @line_height}" <>
        ":box=1:boxcolor=black@0.35:boxborderw=12"
    end)
  end

  # Tira os caracteres que têm significado especial nos filtros do ffmpeg.
  defp sanitize(title), do: String.replace(title, ~r/[:'%,\\]/u, "")

  defp wrap(text, max) do
    text
    |> String.split()
    |> Enum.reduce([], fn
      word, [] ->
        [word]

      word, [line | rest] ->
        if String.length(line) + 1 + String.length(word) <= max,
          do: [line <> " " <> word | rest],
          else: [word, line | rest]
    end)
    |> Enum.reverse()
  end
end
