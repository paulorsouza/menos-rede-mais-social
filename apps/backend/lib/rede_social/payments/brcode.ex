defmodule RedeSocial.Payments.BRCode do
  @moduledoc """
  O "PIX copia e cola" (BR Code), no padrão EMV do Banco Central: campos
  com id, tamanho e valor, e um CRC16 no fim para o aplicativo do banco
  conferir que nada foi digitado errado.
  """

  import Bitwise

  @doc "Código de uma cobrança com valor e identificador (txid)."
  def build(key, amount_cents, txid, name, city) do
    account = field("00", "br.gov.bcb.pix") <> field("01", key)

    payload =
      field("00", "01") <>
        field("01", "12") <>
        field("26", account) <>
        field("52", "0000") <>
        field("53", "986") <>
        field("54", amount(amount_cents)) <>
        field("58", "BR") <>
        field("59", clean(name, 25)) <>
        field("60", clean(city, 15)) <>
        field("62", field("05", txid)) <>
        "6304"

    payload <> crc16(payload)
  end

  @doc "Lê os campos de um código (para os testes e para conferir o CRC)."
  def parse(code) do
    {body, crc} = String.split_at(code, -4)

    # O CRC cobre o código inteiro até o "6304", o próprio campo dele.
    if crc16(body) == crc and String.ends_with?(body, "6304") do
      {:ok, body |> String.slice(0..-5//1) |> fields()}
    else
      {:error, :crc}
    end
  end

  defp fields(""), do: %{}

  defp fields(<<id::binary-2, size::binary-2, rest::binary>>) do
    size = String.to_integer(size)
    <<value::binary-size(size), rest::binary>> = rest
    Map.put(fields(rest), id, value)
  end

  defp field(id, value),
    do: id <> String.pad_leading(Integer.to_string(byte_size(value)), 2, "0") <> value

  defp amount(cents),
    do: "#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"

  # O padrão só aceita letras sem acento no nome e na cidade.
  defp clean(text, max) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^A-Za-z0-9 ]/u, "")
    |> String.upcase()
    |> String.slice(0, max)
  end

  # CRC16-CCITT (polinômio 0x1021, começando em 0xFFFF), em hexadecimal.
  defp crc16(text) do
    text
    |> :binary.bin_to_list()
    |> Enum.reduce(0xFFFF, fn byte, crc ->
      Enum.reduce(1..8, bxor(crc, byte <<< 8), fn _, acc ->
        if (acc &&& 0x8000) != 0,
          do: bxor(acc <<< 1, 0x1021) &&& 0xFFFF,
          else: acc <<< 1 &&& 0xFFFF
      end)
    end)
    |> Integer.to_string(16)
    |> String.pad_leading(4, "0")
  end
end
