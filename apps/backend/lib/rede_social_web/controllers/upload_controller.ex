defmodule RedeSocialWeb.UploadController do
  @moduledoc """
  Envio que retoma de onde parou: o núcleo do protocolo tus 1.0, com as
  extensões creation e termination. Qualquer cliente tus funciona, e o app
  usa o dele (apps/web/src/upload.ts).

    POST   /api/envios       abre um envio (Upload-Length, Upload-Metadata)
    HEAD   /api/envios/:id   quantos bytes já chegaram (Upload-Offset)
    PATCH  /api/envios/:id   manda mais bytes a partir de Upload-Offset
    DELETE /api/envios/:id   desiste

  O Plug.Head do endpoint transforma HEAD em GET, por isso a rota é `get`;
  a resposta de HEAD sai sem corpo do mesmo jeito.
  """
  use RedeSocialWeb, :controller

  alias RedeSocial.Uploads

  action_fallback RedeSocialWeb.FallbackController

  @version "1.0.0"
  @read [length: 1_000_000, read_length: 1_000_000, read_timeout: 60_000]

  def options(conn, _params) do
    conn
    |> tus_headers()
    |> put_resp_header("tus-version", @version)
    |> put_resp_header("tus-extension", "creation,termination")
    |> put_resp_header("tus-max-size", Integer.to_string(Uploads.max_bytes()))
    |> send_resp(:no_content, "")
  end

  def create(conn, _params) do
    with :ok <- check_version(conn),
         {:ok, upload} <-
           Uploads.create(conn.assigns.current_account, length_header(conn), metadata(conn)) do
      conn
      |> tus_headers()
      |> put_resp_header("location", "/api/envios/" <> upload.id)
      |> put_resp_header("upload-offset", "0")
      |> send_resp(:created, "")
    end
  end

  def show(conn, %{"id" => id}) do
    with %{} = upload <- Uploads.get(conn.assigns.current_account, id) do
      conn
      |> tus_headers()
      |> put_resp_header("upload-offset", Integer.to_string(Uploads.offset(upload)))
      |> put_resp_header("upload-length", Integer.to_string(upload.length))
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(:ok, "")
    end
  end

  def update(conn, %{"id" => id}) do
    with :ok <- check_version(conn),
         %{} = upload <- Uploads.get(conn.assigns.current_account, id),
         :ok <- check_content_type(conn),
         :ok <- check_offset(conn, upload) do
      # O corpo é lido aos poucos e cada pedaço vai para o disco na hora.
      {result, conn} = Uploads.append(upload, conn, &read_chunk/1)
      upload = Uploads.finish(upload)

      case result do
        :ok ->
          conn
          |> tus_headers()
          |> put_resp_header("upload-offset", Integer.to_string(Uploads.offset(upload)))
          |> send_resp(:no_content, "")

        {:error, :locked} ->
          send_tus(conn, :locked, "Este envio já está recebendo bytes em outra conexão.")

        {:error, :too_large} ->
          send_tus(
            conn,
            :request_entity_too_large,
            "Chegaram mais bytes do que o tamanho do envio."
          )

        {:error, _reason} ->
          send_tus(
            conn,
            :bad_request,
            "A conexão caiu no meio. Pergunte o Upload-Offset e continue."
          )
      end
    end
  end

  def delete(conn, %{"id" => id}) do
    with %{} = upload <- Uploads.get(conn.assigns.current_account, id) do
      Uploads.delete(upload)
      conn |> tus_headers() |> send_resp(:no_content, "")
    end
  end

  defp read_chunk(conn) do
    case Plug.Conn.read_body(conn, @read) do
      {:more, data, conn} -> {:data, data, conn}
      {:ok, "", conn} -> {:done, conn}
      {:ok, data, conn} -> {:last, data, conn}
      {:error, reason} -> {:error, reason, conn}
    end
  end

  defp tus_headers(conn), do: put_resp_header(conn, "tus-resumable", @version)

  defp check_version(conn) do
    case get_req_header(conn, "tus-resumable") do
      [@version] -> :ok
      _ -> {:error, :tus_version}
    end
  end

  defp check_content_type(conn) do
    case get_req_header(conn, "content-type") do
      ["application/offset+octet-stream" <> _] -> :ok
      _ -> {:error, :tus_content_type}
    end
  end

  defp check_offset(conn, upload) do
    with [value] <- get_req_header(conn, "upload-offset"),
         {offset, ""} <- Integer.parse(value),
         true <- offset == Uploads.offset(upload) do
      :ok
    else
      _ -> {:error, :tus_offset}
    end
  end

  defp length_header(conn) do
    with [value] <- get_req_header(conn, "upload-length"),
         {length, ""} <- Integer.parse(value) do
      length
    else
      _ -> nil
    end
  end

  # Upload-Metadata: "filename ZmlsbWUubXA0,filetype dmlkZW8vbXA0"
  defp metadata(conn) do
    conn
    |> get_req_header("upload-metadata")
    |> List.first("")
    |> String.split(",", trim: true)
    |> Map.new(fn pair ->
      case String.split(String.trim(pair), " ", parts: 2) do
        [key, value] -> {key, Base.decode64(value) |> elem_or_nil()}
        [key] -> {key, nil}
      end
    end)
  end

  defp elem_or_nil({:ok, value}), do: value
  defp elem_or_nil(:error), do: nil

  defp send_tus(conn, status, message) do
    conn |> tus_headers() |> put_status(status) |> json(%{error: message})
  end
end
