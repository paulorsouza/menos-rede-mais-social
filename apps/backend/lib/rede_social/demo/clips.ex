defmodule RedeSocial.Demo.Clips do
  @moduledoc """
  Gera os vídeos da demonstração com o ffmpeg: um fundo animado com o título
  escrito por cima. Sem ffmpeg instalado, a demo sobe sem vídeos.
  """

  alias RedeSocial.Media

  @font "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
  @font_size 40
  @line_height 54

  def available?, do: System.find_executable("ffmpeg") != nil and File.exists?(@font)

  @doc "Gera um vídeo e devolve a URL dele em /uploads."
  def render(title, style, seconds, {width, height} \\ {480, 854}) do
    {path, url} = Media.new_file(".mp4")

    args = [
      "-y",
      "-loglevel",
      "error",
      "-f",
      "lavfi",
      "-i",
      source(style, width, height, seconds),
      "-t",
      Integer.to_string(seconds),
      "-vf",
      text_filter(title),
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-crf",
      "30",
      "-pix_fmt",
      "yuv420p",
      "-movflags",
      "+faststart",
      "-an",
      path
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} -> {:ok, url}
      {output, _status} -> {:error, output}
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
