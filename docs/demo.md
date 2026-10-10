# Roteiro da demonstração

Um passo a passo de uns 10 minutos para apresentar a -rede+social. Cada passo mostra uma ideia do [plano](plano-inicial.md) funcionando de verdade.

## Antes de apresentar

Suba tudo com um comando, na raiz do repositório:

```bash
docker compose up --build
```

Na primeira vez demora alguns minutos: o motor em Rust é compilado, as dependências são baixadas e os vídeos de exemplo são gerados e convertidos. Depois, abra http://localhost:5173.

Para mostrar as legendas automáticas, suba com o perfil delas (o modelo de fala, de 466 MB, é baixado só na primeira vez) e recrie a demo depois, para os vídeos de exemplo saírem legendados:

```bash
docker compose --profile legendas up --build
docker compose exec backend mix demo.reset
```

Para voltar a demo ao estado inicial (apaga posts, contas novas e mídias, e recria tudo):

```bash
docker compose exec backend mix demo.reset
```

## Pessoas de exemplo

| Apelido | Cidade | gov.br | Para mostrar |
| --- | --- | --- | --- |
| maria.silva | Campinas/SP | prata | Feed por grafo e anúncio regional da padaria do bairro |
| joao.pereira | Recife/PE | ouro | Painel do criador com 2,35 milhões de views no mês |
| bia.santos | Salvador/BA | ouro | Shorts de humor |
| ana.costa | Belém/PA | bronze | Publica, mas não recebe por anúncios |
| carlos.souza | Porto Alegre/RS | prata | Música |
| lucas.lima | São Paulo/SP | prata | Tecnologia, longe da bolha da Maria |
| dona.rosa | Campinas/SP | prata | A padaria que anuncia no regional |
| theo.alves | Salvador/BA | bronze, menor de idade | Perfil privado e nenhum anúncio |
| moderacao.lia | Brasília/DF | prata | Moderação: remove citando a regra |
| moderacao.davi | Brasília/DF | prata | Moderação: julga o recurso contra a remoção da Lia |
| juridico.rui | Brasília/DF | prata | Setor jurídico: registra a ordem judicial |
| promo.relampago | São Paulo/SP | bronze | Publica um golpe: aviso e recurso |

Todas são fictícias, assim como os anunciantes e os valores.

## Roteiro

1. **A proposta e o logo.** Na tela de entrada, o logo se lê "rede social". Mostre os detalhes: "rede" é fino e apagado, "social" é forte, um traço de menos vem antes de "rede" e um sinal de mais ocupa o espaço entre as palavras. Menos rede, mais social. O login gov.br é simulado de propósito.
2. **Entrar como a Maria.** Clique no avatar dela. O feed abre no modo "meio a meio". Toque no "?" de dois posts seguidos: um aparece porque ela segue a pessoa e "20 pessoas que curtem o que você curte também curtiram", o outro porque "ninguém perto de você chegou aqui ainda". Não existe tema nem tag em lugar nenhum: é só o grafo de quem curtiu o quê.
3. **Trocar o modo do feed.** Abra o seletor no topo e passe por "Na bolha", "Furando a bolha" e "Por data". Depois abra a aba "Em alta", com o ícone de chama: é a mesma lista para todo mundo, sem grafo nenhum. Fora da bolha, Ana, Lucas e João se revezam, um autor de cada vez. O ícone do chip ao lado mostra que a ordem foi calculada pelo motor aberto, com a versão e o hash dos parâmetros.
4. **Publicar.** Clique em "O que está acontecendo?" e escreva "feijoada na feira do bairro". Não tem tag nem tipo para escolher. O contador só aparece perto dos 140 caracteres, não existe botão de responder e Ctrl+Enter publica. Foto e vídeo usam o mesmo campo: anexe o arquivo e o tipo sai dele, vídeo em pé vira short.
5. **A bolha segue o que a pessoa faz.** Não existe tela de interesses. No modo "Furando a bolha", curta dois posts do Lucas. Volte para "Na bolha": os posts dele e os da Ana aparecem, com "20 pessoas que curtem o que você curte também curtiram", porque quem curte o Lucas também curte a Ana. Em "Furando a bolha" sobra só o futebol do João. Descurtir desfaz.
6. **Shorts.** Role seis shorts. O sétimo item é um anúncio regional da Padaria Dona Rosa, porque a Maria é de Campinas. Abra "Para onde vai o dinheiro": aparece quanto cada criador recebeu, pelo tempo assistido, calculado pelo motor.
7. **Vídeos.** Abra o vídeo do João: o anúncio entra no início porque ele marcou esse ponto, e a barra mostra os pontos escolhidos. Depois abra o vídeo da Ana: sem anúncio, porque a conta dela é bronze.
8. **Painel do criador.** Saia e entre como o João. O número grande é o pagamento estimado do mês, e a barra mostra em que faixa ele está. Abra "Ver a conta" e explique que crescer nunca diminui o total, como no imposto de renda.
9. **Transparência.** Mostre os hashes do `params/feed.toml` e do `params/ads.toml`, abra o arquivo em uso e diga que qualquer pessoa pode rodar `sha256sum params/feed.toml` no repositório e conferir. Passe por quem anunciou e pelo link das regras pétreas.
10. **Conta nova pelo gov.br simulado.** Saia, clique em "Entrar com gov.br", gere um CPF de teste no ícone do dado e crie a conta. Depois tente de novo com o mesmo CPF: a rede recusa, sem nunca ter guardado o número. No perfil aparece só o apelido e o selo.
11. **Temas.** No menu da conta (o avatar), troque entre claro, escuro, lima e nerd. No nerd, o logo vira `-rede +social`, como flags de um comando no terminal.
12. **Moderação.** Entre como a Lia e abra "Moderação" no menu da conta. Tem duas denúncias: um golpe de "mande o código do SMS", com três denúncias pela regra 6, e o post do Lucas sobre a audiência pública, denunciado como discriminação. Remova o golpe (a regra já vem escolhida) e mantenha o post do Lucas. Mostre que a denúncia, para quem usa a rede, fica dentro do "?" de cada post.
13. **Aviso e recurso.** Entre como `promo.relampago`, o autor do golpe. O ponto vermelho no avatar avisa; em "Avisos" está a regra usada. Recorra. Volte como a Lia: o recurso aparece, mas ela não pode julgar, porque foi ela quem removeu. Entre como o Davi e decida.
14. **Menor de idade.** Como a Maria, abra o perfil do Theo: é privado, porque ele não segue a Maria. Seguir não basta, ele precisa seguir de volta. Os posts dele nunca aparecem em "Em alta" nem como sugestão, e ele não vê anúncio nos shorts.
15. **Ordem judicial.** Entre como o Rui, abra "Ordens judiciais" e registre uma ordem para `maria.silva`. Toque em dois guardiões: o "Abrir" continua travado. Toque no terceiro e abra: o CPF e os acessos aparecem uma única vez. Mostre na transparência que a abertura entrou no registro com o juízo e a data, sem o apelido de ninguém, e o hash do `params/guardioes.toml`.
16. **Seus dados.** No menu da conta, "Seus dados" baixa um arquivo com tudo o que a rede guarda e apaga a conta. O arquivo não tem CPF, porque a rede não guarda o número.
17. **Conferir o feed sem confiar na rede.** Como a Maria, toque no chip do motor e em "Baixar a conta deste feed". Na transparência, baixe as entradas do registro. No terminal, rode `cargo run -p verificador -- feed conta-do-feed.json --parametros ../params/feed.toml --registro entradas.json` dentro de `services/`: o verificador refaz a ordem do feed, confere o recibo assinado pelo motor e mostra que cada curtida usada estava no retrato do grafo publicado. Mude um número no arquivo e rode de novo: ele aponta o que não confere.
18. **Publicar um vídeo.** Como a Maria, anexe um vídeo no campo de publicar. A barra no pé do vídeo é o envio, que começa na hora, enquanto você escreve a legenda; se a conexão cair, ele continua de onde parou. Publique: o post aparece "processando" só para você e, segundos depois, vira vídeo com capa. Na transparência, a seção de custo mostra quanto cada vídeo convertido gastou.
19. **Economizar dados.** No menu da conta, ligue "Economizar dados": o player não passa de 360 e nada é baixado antes do play. Num celular com economia de dados ou em 2G, o modo já começa ligado.
20. **Legendas.** Com o perfil de legendas, os vídeos de exemplo têm uma voz sintética lendo a legenda do post. Nos shorts, que começam sem som, a legenda automática aparece sozinha. A voz é robótica, então o whisper erra mais do que erraria com gente falando.
21. **Live.** No campo de publicar, o ícone de antena abre a tela de live: a câmera aparece e "Começar live" põe no ar. Numa janela anônima, entre como a Rafa, que segue a Maria: a live aparece no topo de Vídeos, com o selo "Ao vivo". Encerre: em alguns segundos a gravação vira vídeo no perfil da Maria. "Transmitir pelo OBS" mostra o servidor e a chave.
22. **Quanto custa uma hora de vídeo.** Na transparência, a tabela mostra o medido nos vídeos da demo ao lado do teto que `params/video.toml` permite: guardar, converter e entregar em cada qualidade.

## O que é real e o que é simulado

Funciona de verdade nesta demo:

- O motor de feed (por grafo, sem categoria nenhuma) e o de anúncios, em Rust, com os parâmetros públicos de `params/`.
- O "por que estou vendo isto", o rateio dos shorts e o pagamento por faixas, todos calculados pelo motor.
- A impressão digital do CPF, que impede contas duplicadas sem guardar o número.
- O cofre do CPF: cada conta tem o CPF selado com a chave dos guardiões, e a ordem judicial abre com 3 de 5, com as provas conferidas pelo motor. Só as fatias dos guardiões são de teste, para a demo funcionar sem as instituições.
- O registro público, o recibo assinado de cada feed, os retratos do grafo e o verificador aberto. O build do motor com Nix é reproduzível.
- O vídeo: armazenamento S3 (Garage), conversão em HLS na fila, envio que retoma, capas, legendas automáticas, modo econômico, lives com gravação e o custo por hora medido.
- Os registros de acesso com o IP selado, a moderação com recurso, as regras de menores, baixar os dados e apagar a conta.
- As regras de publicação: conta básica não publica, e só prata ou ouro recebe por anúncios.

É simulado ou ainda não existe:

- O gov.br (o Login Único já está integrado, mas sem credencial a demo usa o simulado), os CPFs, as pessoas, os anunciantes e os valores.
- As fatias dos guardiões, que na demo ficam em `services/cofre/demo/` e no piloto ficam nos cofres de hardware de cada instituição.
- A atestação de hardware, que só faz sentido com a rede rodando em servidores de verdade.
- A CDN: na demo, um nginx faz o papel dela. Os preços da conta de custo por hora são ilustrativos.
- Os vídeos de exemplo, gerados pelo ffmpeg, e a voz deles, sintética.
