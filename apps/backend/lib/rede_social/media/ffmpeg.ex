defmodule RedeSocial.Media.FFmpeg do
  @moduledoc """
  O que a rede pede ao ffmpeg: ler um arquivo, converter vídeo em HLS com
  vários degraus de qualidade, tirar a capa, limpar fotos e extrair o áudio
  para as legendas.

  Toda conversão roda com `-benchmark`, que informa o tempo de CPU gasto. É
  esse número que entra na conta do custo por hora de vídeo.
  """

  require Logger

  alias RedeSocial.Media.Params

  @image_formats ~w(image2 png_pipe jpeg_pipe webp_pipe bmp_pipe tiff_pipe gif)

  @doc """
  Lê largura, altura (já girada, do jeito que aparece na tela), duração e se
  tem áudio. Vídeo gravado no navegador às vezes chega sem duração: aí
  `duration_ms` fica nil.
  """
  def probe(path) do
    # Só o JSON na saída: avisos do ffprobe (EXIF estranho, por exemplo)
    # estragariam a leitura.
    args = ~w(-v quiet -print_format json -show_format -show_streams) ++ [path]

    with {output, 0} <- System.cmd("ffprobe", args),
         {:ok, %{"format" => format} = info} <- Jason.decode(output),
         %{} = video <- Enum.find(info["streams"] || [], &(&1["codec_type"] == "video")) do
      {width, height} = displayed_size(video)
      photo? = format["format_name"] in @image_formats

      {:ok,
       %{
         type: if(photo?, do: :photo, else: :video),
         format: format["format_name"],
         width: width,
         height: height,
         duration_ms: if(photo?, do: nil, else: duration_ms(format["duration"])),
         has_audio: Enum.any?(info["streams"], &(&1["codec_type"] == "audio"))
       }}
    else
      _ -> {:error, :unsupported_file}
    end
  end

  # Celular grava deitado e marca a rotação; quem assiste vê em pé.
  defp displayed_size(%{"width" => width, "height" => height} = stream) do
    rotation =
      Enum.find_value(stream["side_data_list"] || [], & &1["rotation"]) ||
        String.to_integer(get_in(stream, ["tags", "rotate"]) || "0")

    if rem(abs(rotation), 180) == 90, do: {height, width}, else: {width, height}
  end

  defp duration_ms(nil), do: nil

  defp duration_ms(seconds) do
    case Float.parse(seconds) do
      {value, _} when value > 0 -> round(value * 1000)
      _ -> nil
    end
  end

  @doc """
  Foto em WebP, sem os metadados da câmera (inclusive a localização) e com o
  lado maior limitado. GIF passa como veio, porque pode ser animado e não
  carrega esses metadados.
  """
  def photo(source, %{format: "gif"}, out_dir) do
    target = Path.join(out_dir, "foto.gif")
    File.cp!(source, target)
    {:ok, target}
  end

  def photo(source, _probe, out_dir) do
    %{"max_side" => max_side, "quality" => quality} = Params.photo()
    target = Path.join(out_dir, "foto.webp")

    fit =
      "scale=w='min(iw,#{max_side})':h='min(ih,#{max_side})':force_original_aspect_ratio=decrease"

    run(
      ~w(-y -hide_banner -nostats -loglevel error -i) ++
        [source, "-map_metadata", "-1", "-frames:v", "1", "-vf", fit] ++
        ["-c:v", "libwebp", "-quality", to_string(quality), target],
      target
    )
  end

  @doc """
  Os degraus que valem para um vídeo deste tamanho: só até o lado menor do
  vídeo enviado. Vídeo menor que o primeiro degrau sai num degrau só, do
  tamanho dele.
  """
  def renditions(%{width: width, height: height}, ladder) do
    short = min(width, height)

    case Enum.filter(ladder, &(&1["short_side"] <= short)) do
      [] -> [%{List.first(ladder) | "short_side" => even(short)}]
      steps -> steps
    end
  end

  @doc """
  Converte o vídeo em HLS (pedaços fMP4, H.264 e AAC), um degrau por pasta,
  com a lista principal em master.m3u8. Devolve os degraus, os bytes de cada
  um e o tempo de CPU gasto.
  """
  def hls(source, probe, out_dir) do
    steps = Enum.with_index(renditions(probe, Params.ladder()))
    segment = Params.segment_seconds()
    audio? = probe.has_audio

    args =
      ~w(-y -hide_banner -nostats -loglevel level+info -benchmark -i) ++
        [source, "-filter_complex", filter(steps, probe)] ++
        Enum.flat_map(steps, fn {_step, i} -> ["-map", "[v#{i}]"] end) ++
        if(audio?, do: Enum.flat_map(steps, fn _ -> ["-map", "0:a:0"] end), else: []) ++
        ~w(-c:v libx264 -preset veryfast -profile:v main -pix_fmt yuv420p -sc_threshold 0) ++
        ["-crf", to_string(Params.crf())] ++
        ["-force_key_frames", "expr:gte(t,n_forced*#{segment})"] ++
        if(audio?, do: ~w(-c:a aac -ac 2), else: []) ++
        Enum.flat_map(steps, &rates(&1, audio?)) ++
        ~w(-f hls -hls_playlist_type vod -hls_segment_type fmp4 -hls_flags independent_segments) ++
        ["-hls_time", to_string(segment), "-hls_fmp4_init_filename", "init.mp4"] ++
        ["-hls_segment_filename", Path.join(out_dir, "%v/s%04d.m4s")] ++
        ["-master_pl_name", "master.m3u8", "-var_stream_map", stream_map(steps, audio?)] ++
        [Path.join(out_dir, "%v/index.m3u8")]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {output, 0} ->
        renditions =
          Enum.map(steps, fn {step, _i} ->
            %{
              short_side: step["short_side"],
              video_kbps: step["video_kbps"],
              audio_kbps: if(audio?, do: step["audio_kbps"], else: 0),
              bytes: dir_bytes(Path.join(out_dir, to_string(step["short_side"])))
            }
          end)

        {:ok, Map.put(benchmark(output), :renditions, renditions)}

      {output, status} ->
        Logger.error("ffmpeg saiu com #{status}: #{errors(output)}")
        {:error, {:ffmpeg, errors(output)}}
    end
  end

  # Um decodificador só, dividido em um redimensionamento por degrau.
  defp filter(steps, probe) do
    vertical? = probe.height > probe.width

    scales =
      Enum.map_join(steps, ";", fn {%{"short_side" => side}, i} ->
        size = if vertical?, do: "w=#{side}:h=-2", else: "w=-2:h=#{side}"
        "[s#{i}]scale=#{size}[v#{i}]"
      end)

    case length(steps) do
      1 -> String.replace(scales, "[s0]", "[0:v]")
      n -> "[0:v]split=#{n}#{Enum.map_join(0..(n - 1), &"[s#{&1}]")};" <> scales
    end
  end

  defp rates({step, i}, audio?) do
    kbps = step["video_kbps"]

    ["-maxrate:v:#{i}", "#{kbps}k", "-bufsize:v:#{i}", "#{kbps * 2}k"] ++
      if audio?, do: ["-b:a:#{i}", "#{step["audio_kbps"]}k"], else: []
  end

  defp stream_map(steps, audio?) do
    Enum.map_join(steps, " ", fn {%{"short_side" => side}, i} ->
      if audio?, do: "v:#{i},a:#{i},name:#{side}", else: "v:#{i},name:#{side}"
    end)
  end

  @doc "Uma capa em WebP, tirada perto do começo do vídeo."
  def poster(source, probe, out_dir) do
    target = Path.join(out_dir, "capa.webp")
    at = if probe.duration_ms, do: min(1.0, probe.duration_ms / 3000), else: 0
    side = min(720, even(min(probe.width, probe.height)))
    size = if probe.height > probe.width, do: "#{side}:-2", else: "-2:#{side}"

    run(
      ~w(-y -hide_banner -nostats -loglevel error -ss) ++
        [to_string(at), "-i", source, "-frames:v", "1", "-map_metadata", "-1"] ++
        ["-vf", "scale=#{size}", "-c:v", "libwebp", "-quality", "75", target],
      target
    )
  end

  @doc "O áudio em WAV mono de 16 kHz, o formato que o whisper espera."
  def audio(source, target) do
    run(
      ~w(-y -hide_banner -nostats -loglevel error -i) ++
        [source | ~w(-vn -ac 1 -ar 16000 -c:a pcm_s16le)] ++ [target],
      target
    )
  end

  @doc "Junta os pedaços de uma gravação (todos no mesmo formato) num arquivo só."
  def concat(parts, target) do
    list = target <> ".txt"
    File.write!(list, Enum.map_join(parts, "\n", &"file '#{escape_quote(&1)}'"))

    result =
      run(
        ~w(-y -hide_banner -nostats -loglevel error -f concat -safe 0 -i) ++
          [list | ~w(-c copy -movflags +faststart)] ++ [target],
        target
      )

    File.rm(list)
    result
  end

  defp escape_quote(path), do: String.replace(path, "'", ~S('\''))

  defp run(args, target) do
    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, target}

      {output, status} ->
        Logger.error("ffmpeg saiu com #{status}: #{output}")
        {:error, {:ffmpeg, output}}
    end
  end

  # bench: utime=0.821s stime=0.210s rtime=0.257s
  defp benchmark(output) do
    case Regex.run(~r/bench: utime=([\d.]+)s stime=([\d.]+)s rtime=([\d.]+)s/, output) do
      [_, user, system, real] -> %{cpu_ms: ms(user) + ms(system), wall_ms: ms(real)}
      nil -> %{cpu_ms: nil, wall_ms: nil}
    end
  end

  defp ms(seconds), do: seconds |> Float.parse() |> elem(0) |> Kernel.*(1000) |> round()

  defp dir_bytes(dir),
    do: dir |> File.ls!() |> Enum.map(&File.stat!(Path.join(dir, &1)).size) |> Enum.sum()

  defp errors(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["[error]", "[fatal]"]))
    |> Enum.join("\n")
  end

  defp even(value), do: value - rem(value, 2)
end
