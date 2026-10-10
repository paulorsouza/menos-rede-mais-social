# Fatias de demonstração

Estes cinco arquivos são as fatias secretas dos guardiões **da demonstração**.
Eles estão no repositório só para a demo conseguir mostrar uma ordem judicial
de ponta a ponta sem cinco instituições na sala.

Nunca use estas fatias fora da demonstração. No piloto, a cerimônia acontece
com as instituições de verdade, num computador desligado da rede, e cada fatia
vai direto para o cofre de hardware do seu guardião.

A parte pública destas fatias está em `params/guardioes.toml`. Para gerar um
conjunto novo:

    cargo run -p cofre -- cerimonia --minimo 3 --saida <pasta> "Nome 1" ... "Nome 5"
