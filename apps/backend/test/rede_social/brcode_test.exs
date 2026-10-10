defmodule RedeSocial.BRCodeTest do
  use ExUnit.Case, async: true

  alias RedeSocial.Payments.BRCode

  # Exemplo do manual do BR Code do Banco Central.
  @bcb_example "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000" <>
                 "5204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D"

  test "lê o exemplo do Banco Central e confere o CRC" do
    assert {:ok, fields} = BRCode.parse(@bcb_example)
    assert fields["59"] == "Fulano de Tal"
    assert fields["58"] == "BR"
  end

  test "um caractere trocado não passa no CRC" do
    assert BRCode.parse(String.replace(@bcb_example, "Fulano", "Fulana")) == {:error, :crc}
  end

  test "a cobrança leva a chave, o valor e o identificador" do
    code =
      BRCode.build("pix@rede-social.demo", 4_800, "campanha7ABC", "Rede Social Demo", "Brasília")

    assert {:ok, fields} = BRCode.parse(code)
    assert fields["54"] == "48.00"
    assert fields["26"] =~ "pix@rede-social.demo"
    assert fields["62"] == "0512campanha7ABC"
    assert fields["60"] == "BRASILIA"
  end
end
