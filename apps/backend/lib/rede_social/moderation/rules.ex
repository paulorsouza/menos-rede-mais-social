defmodule RedeSocial.Moderation.Rules do
  @moduledoc """
  Regras de conteúdo da rede.

  A rede remove o que a lei manda remover e pouco mais (seção 5 do plano).
  Cada regra tem número, texto simples, um exemplo e a base legal, e toda
  remoção cita uma delas. O texto é uma proposta: a versão final depende da
  revisão jurídica antes do piloto, e mudar uma regra passa por RFC.

  A regra 9 não aparece para quem denuncia: só a moderação usa, quando chega
  uma ordem judicial.
  """

  @rules [
    %{
      number: 1,
      title: "Abuso sexual de crianças e adolescentes",
      text:
        "Qualquer conteúdo sexual com menores de 18 anos. Sai na hora e é comunicado às autoridades.",
      example: "Foto íntima de um adolescente, mesmo que ele mesmo tenha mandado.",
      law: "ECA, arts. 240 a 241-E",
      reportable: true
    },
    %{
      number: 2,
      title: "Ameaça e incitação à violência",
      text: "Ameaçar alguém ou chamar outras pessoas para agredir uma pessoa ou um grupo.",
      example: "Publicar onde alguém mora dizendo que ele merece apanhar.",
      law: "Código Penal, arts. 147 e 286",
      reportable: true
    },
    %{
      number: 3,
      title: "Discriminação",
      text:
        "Ofender ou pregar ódio contra alguém por raça, cor, etnia, religião, origem, deficiência, gênero ou orientação sexual.",
      example: "Dizer que pessoas de um grupo são inferiores e não deveriam ter direitos.",
      law: "Lei 7.716/1989 e STF, ADO 26",
      reportable: true
    },
    %{
      number: 4,
      title: "Imagem íntima sem consentimento",
      text: "Nudez ou sexo de uma pessoa que não autorizou a publicação.",
      example: "Vídeo íntimo de uma ex-namorada publicado por vingança.",
      law: "Marco Civil, art. 21, e Código Penal, art. 218-C",
      reportable: true
    },
    %{
      number: 5,
      title: "Dados pessoais de outra pessoa",
      text: "Expor CPF, endereço, telefone ou documentos de alguém sem autorização.",
      example: "Foto do RG de outra pessoa.",
      law: "LGPD",
      reportable: true
    },
    %{
      number: 6,
      title: "Golpe",
      text: "Tentar enganar pessoas para tirar dinheiro ou dados delas.",
      example: "Falsa promoção pedindo o código que chegou por SMS.",
      law: "Código Penal, art. 171",
      reportable: true
    },
    %{
      number: 7,
      title: "Venda de produto proibido",
      text: "Oferecer drogas, armas, remédios controlados ou outros produtos de venda proibida.",
      example: "Anúncio de venda de arma sem registro.",
      law: "Lei 11.343/2006 e Lei 10.826/2003",
      reportable: true
    },
    %{
      number: 8,
      title: "Spam e automação",
      text:
        "Publicar a mesma coisa em massa ou usar robôs para inflar curtidas e views. Protege o grafo e o dinheiro dos criadores.",
      example: "Cem posts iguais com o mesmo link em uma hora.",
      law: "Regra da rede",
      reportable: true
    },
    %{
      number: 9,
      title: "Ordem judicial",
      text:
        "Conteúdo que um juiz mandou remover. O pedido entra no relatório de transparência, e o número do processo também, quando não for sigiloso.",
      example: "Decisão que manda tirar do ar um vídeo considerado difamatório.",
      law: "Marco Civil, art. 19",
      reportable: false
    }
  ]

  @numbers Enum.map(@rules, & &1.number)
  @reportable for rule <- @rules, rule.reportable, do: rule.number

  def all, do: @rules
  def valid?(number), do: number in @numbers
  def reportable?(number), do: number in @reportable
  def get(number), do: Enum.find(@rules, &(&1.number == number))
end
