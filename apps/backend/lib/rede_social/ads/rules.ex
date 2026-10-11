defmodule RedeSocial.Ads.Rules do
  @moduledoc """
  Regras públicas para anúncios. A moderação cita uma delas quando recusa
  uma campanha, do mesmo jeito que nas remoções de posts.
  """

  @rules [
    %{
      number: 1,
      title: "Propaganda política ou eleitoral",
      text:
        "Partido, candidato ou causa eleitoral não anunciam, nem fora de eleição (regra pétrea 10)."
    },
    %{
      number: 2,
      title: "Golpe ou promessa enganosa",
      text: "Ganho fácil, pedido de senha ou código, produto que não existe."
    },
    %{
      number: 3,
      title: "Produto ou serviço proibido por lei",
      text: "O que a lei não deixa vender ou anunciar."
    },
    %{
      number: 4,
      title: "Quebra as regras de conteúdo",
      text: "O anúncio segue as mesmas regras de qualquer post."
    },
    %{
      number: 5,
      title: "Apostas",
      text: "Casa de apostas, bet, cassino e jogo de azar não anunciam."
    },
    %{
      number: 6,
      title: "Publicidade de governo",
      text:
        "Órgão público não anuncia a própria gestão, obra ou realização. Só vale campanha de utilidade pública, como vacinação, defesa civil e prazos de documentos."
    }
  ]

  def all, do: @rules
  def get(number), do: Enum.find(@rules, &(&1.number == number))
end
