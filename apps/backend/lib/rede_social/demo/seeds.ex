defmodule RedeSocial.Demo.Seeds do
  @moduledoc """
  Dados da demonstração: pessoas, posts, fotos, shorts, vídeos e anúncios.

  Roda uma vez só. Se as pessoas de exemplo já existem, não faz nada. Todos os
  nomes, lugares e anunciantes são fictícios, e os CPFs são de teste.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias RedeSocial.{Accounts, Ads, Media, Moderation, Payments, Repo, Social}
  alias RedeSocial.Accounts.{CNPJ, CPF}
  alias RedeSocial.Ads.{AdView, Advertiser, Campaign}
  alias RedeSocial.Payments.Pix
  alias RedeSocial.Demo.{Art, Clips}
  alias RedeSocial.Transparency.Quarterly
  alias RedeSocial.Social.{Like, Post, Save, View}

  @personas [
    %{
      nickname: "maria.silva",
      level: :prata,
      region: "Campinas/SP",
      bio: "Cozinho todo domingo e divido as receitas por aqui.",
      tastes: [:cozinha, :musica],
      monthly_views: 140_000
    },
    %{
      nickname: "joao.pereira",
      level: :ouro,
      region: "Recife/PE",
      bio: "Comento futebol da várzea à final de campeonato.",
      tastes: [:futebol, :humor],
      monthly_views: 2_350_000
    },
    %{
      nickname: "bia.santos",
      level: :ouro,
      region: "Salvador/BA",
      bio: "Humor do dia a dia em vídeos curtos.",
      tastes: [:humor, :cozinha],
      monthly_views: 860_000
    },
    %{
      nickname: "ana.costa",
      level: :bronze,
      region: "Belém/PA",
      bio: "Bióloga. Falo de floresta, rio e ciência sem complicar.",
      tastes: [:ciencia],
      monthly_views: 12_000
    },
    %{
      nickname: "carlos.souza",
      level: :prata,
      region: "Porto Alegre/RS",
      bio: "Violão, samba e um pouco de rock gaúcho.",
      tastes: [:musica],
      monthly_views: 45_000
    },
    %{
      nickname: "lucas.lima",
      level: :prata,
      region: "São Paulo/SP",
      bio: "Professor e programador. Tecnologia explicada no ônibus.",
      tastes: [:ciencia],
      monthly_views: 3_000
    },
    %{
      nickname: "dona.rosa",
      level: :prata,
      region: "Campinas/SP",
      bio: "Padaria Dona Rosa. Pão quentinho às 6h.",
      tastes: [:cozinha],
      monthly_views: 8_000
    },
    # Menor de idade: o perfil é privado, então só quem ele segue vê os posts,
    # e ele não vê anúncio nenhum.
    %{
      nickname: "theo.alves",
      level: :bronze,
      age_band: :minor,
      region: "Salvador/BA",
      bio: "Desenho e skate.",
      tastes: [:humor, :musica],
      monthly_views: 0
    },
    # Conta que publica um golpe, para mostrar denúncia, aviso e recurso.
    %{
      nickname: "promo.relampago",
      level: :bronze,
      region: "São Paulo/SP",
      bio: "Promoções todo dia!",
      tastes: [],
      monthly_views: 0
    },
    # Setor jurídico da entidade gestora: registra as ordens judiciais.
    %{
      nickname: "juridico.rui",
      level: :prata,
      region: "Brasília/DF",
      bio: "Setor jurídico da entidade gestora.",
      tastes: [],
      monthly_views: 0,
      legal_officer: true
    },
    # Equipe de moderação. São duas para mostrar que quem removeu um post
    # nunca julga o recurso contra a própria decisão.
    %{
      nickname: "moderacao.lia",
      level: :prata,
      region: "Brasília/DF",
      bio: "Equipe de moderação.",
      tastes: [],
      monthly_views: 0,
      moderator: true
    },
    %{
      nickname: "moderacao.davi",
      level: :prata,
      region: "Brasília/DF",
      bio: "Equipe de moderação.",
      tastes: [],
      monthly_views: 0,
      moderator: true
    }
  ]

  # Descrição de cada ilustração, para quem usa leitor de tela.
  @scene_alt %{
    food: "Ilustração de uma mesa posta com travessas de comida.",
    food2: "Ilustração de um prato de cuscuz enfeitado com ovo e tomate.",
    sunset: "Ilustração de um farol no fim de tarde, com o céu alaranjado.",
    river: "Ilustração de um rio largo ao amanhecer, com mata nas margens.",
    music: "Ilustração de um violão sobre um fundo azul, com notas musicais.",
    field: "Ilustração de um campo de várzea molhado, com as traves ao fundo.",
    bread: "Ilustração de pães saindo do forno numa assadeira.",
    tech: "Ilustração de computadores enfileirados numa sala de aula.",
    lily: "Ilustração de folhas de vitória-régia na água do igarapé.",
    city: "Ilustração de casarões coloridos de um centro histórico."
  }

  # Grupos do público simulado. Só os dados de exemplo usam isso, para que
  # as curtidas tenham cara de gente de verdade: quem gosta de cozinha curte
  # receita, quem gosta de futebol curte futebol. A rede não guarda nem
  # conhece esses grupos; ela só vê quem curtiu o quê.
  @audiences [:cozinha, :futebol, :humor, :ciencia, :musica]

  @follows %{
    "maria.silva" => ~w(dona.rosa carlos.souza bia.santos theo.alves),
    "joao.pereira" => ~w(bia.santos carlos.souza),
    "bia.santos" => ~w(joao.pereira maria.silva),
    "ana.costa" => ~w(lucas.lima maria.silva),
    "carlos.souza" => ~w(maria.silva joao.pereira),
    "lucas.lima" => ~w(ana.costa joao.pereira),
    "dona.rosa" => ~w(maria.silva),
    # O Theo segue a Bia e o Carlos, então só os dois veem os posts dele. A
    # Maria segue o Theo, mas isso não basta: ele não segue a Maria.
    "theo.alves" => ~w(bia.santos carlos.souza)
  }

  # Público que curte, salva e assiste. São contas bronze, sem posts.
  @first_names ~w(rafa duda leo bruna caio lari thiago gabi pedro julia matheus nanda vitor camila diego leticia renan paula igor manu)
  @last_names ~w(moura alves rocha nunes freitas campos ribeiro teixeira duarte pinto)
  @regions [
    "Campinas/SP",
    "Recife/PE",
    "Salvador/BA",
    "Belém/PA",
    "Porto Alegre/RS",
    "São Paulo/SP",
    "Belo Horizonte/MG",
    "Manaus/AM"
  ]

  # {autor, texto, público, horas atrás, curtidas}
  @text_posts [
    {"theo.alves", "Terminei o desenho do skate novo. Agora falta coragem de andar nele.", [], 5,
     0},
    {"maria.silva",
     "Pão de queijo de domingo saiu do forno. O segredo é polvilho azedo e paciência.",
     [:cozinha], 3, 45},
    {"maria.silva", "Feira do bairro hoje com caqui a preço de banana. Corre que ainda dá tempo.",
     [:cozinha], 20, 18},
    {"maria.silva",
     "Saí do teatro municipal pensando na peça a semana inteira. Teatro bom é assim.", [:musica],
     40, 12},
    {"maria.silva",
     "Bolo de cenoura com cobertura que endurece: o truque é ferver o chocolate por um minuto.",
     [:cozinha], 68, 39},
    {"joao.pereira",
     "Clássico de domingo: quem não marca, toma. Meu palpite é 2 a 1 e muita reclamação de pênalti.",
     [:futebol], 2, 44},
    {"joao.pereira",
     "Várzea é o futebol mais honesto do Brasil. Ninguém ganha nada e todo mundo dá a vida em campo.",
     [:futebol], 26, 40},
    {"joao.pereira", "O juiz deu 9 minutos de acréscimo. Meu coração deu 3.", [:futebol, :humor],
     8, 46},
    {"joao.pereira", "Torcedor de time pequeno sofre o dobro e comemora o triplo.", [:futebol],
     70, 33},
    {"bia.santos",
     "Fui ao mercado comprar pão e voltei com três panelas, um ventilador e nenhum pão.",
     [:humor], 5, 43},
    {"bia.santos",
     "Pôr do sol no farol continua de graça e continua sendo o melhor espetáculo da cidade.",
     [:humor], 30, 36},
    {"bia.santos", "Minha tia manda áudio de 7 minutos para dizer que está tudo bem.", [:humor],
     12, 45},
    {"bia.santos", "Ônibus lotado, chuva e guarda-chuva quebrado. Salvador me testando hoje.",
     [:humor], 18, 38},
    {"ana.costa",
     "Hoje medimos a temperatura do rio às 5h da manhã. A floresta acorda antes de todo mundo.",
     [:ciencia], 6, 25},
    {"ana.costa",
     "Por que o rio Negro é escuro? Folhas. Muita folha se decompondo e soltando ácidos na água.",
     [:ciencia], 22, 34},
    {"ana.costa",
     "Açaí aqui em Belém é almoço: com peixe frito e farinha. Sobremesa é coisa de turista.",
     [:cozinha, :musica], 44, 27},
    {"ana.costa",
     "Vaga-lume é sinal de rio limpo. Se tem vaga-lume perto de você, cuida desse lugar.",
     [:ciencia], 34, 29},
    {"carlos.souza",
     "Ensaio de quinta: três violões, um pandeiro e o vizinho cantando junto da janela.",
     [:musica], 4, 22},
    {"carlos.souza",
     "Disco novo de uma banda daqui de Porto Alegre e eu já decorei todas as letras.", [:musica],
     28, 15},
    {"carlos.souza",
     "Roda de samba no domingo à tarde na praça. Leva tua voz que instrumento a gente arruma.",
     [:musica], 48, 19},
    {"carlos.souza", "Afinar violão no frio de Porto Alegre é um exercício de fé.",
     [:musica, :humor], 65, 24},
    {"lucas.lima",
     "Senha forte é frase longa. \"cafe com leite na padaria da esquina\" é melhor que S3nh@!",
     [:ciencia], 7, 31},
    {"lucas.lima",
     "Ensinei lógica de programação usando receita de bolo. Funcionou melhor que qualquer slide.",
     [:ciencia], 24, 26},
    {"lucas.lima",
     "Código aberto não é código sem dono. É código que qualquer pessoa pode conferir.",
     [:ciencia], 36, 40},
    {"lucas.lima",
     "Audiência pública sobre o transporte da cidade amanhã às 19h na câmara. Vale ir e perguntar.",
     [:ciencia], 10, 21},
    {"dona.rosa",
     "Fornada das 6h saindo: francês, pão de leite e o famoso pão de linguiça. Chega cedo!",
     [:cozinha], 1, 16},
    {"dona.rosa", "Sexta tem bolo de fubá com goiabada. Encomendas direto no balcão da padaria.",
     [:cozinha], 32, 11}
  ]

  # {autor, legenda, público, horas atrás, curtidas, ilustração}
  @photo_posts [
    {"maria.silva", "Mesa de domingo.", [:cozinha], 9, 36, :food},
    {"bia.santos", "Fim de tarde no farol.", [:humor], 14, 44, :sunset},
    {"ana.costa", "Rio às 5h da manhã.", [:ciencia], 16, 42, :river},
    {"carlos.souza", "Ensaio de quinta.", [:musica], 21, 20, :music},
    {"joao.pereira", "Campo de várzea depois da chuva.", [:futebol], 38, 41, :field},
    {"dona.rosa", "Primeira fornada do dia.", [:cozinha], 2, 23, :bread},
    {"lucas.lima", "Laboratório de informática da escola, montado com doações.", [:ciencia], 46,
     28, :tech},
    {"ana.costa", "Vitória-régia no igarapé.", [:ciencia], 58, 33, :lily},
    {"maria.silva", "Cuscuz paulista para o almoço de família.", [:cozinha], 62, 26, :food2},
    {"bia.santos", "Casarões coloridos do centro histórico.", [:humor, :musica], 72, 39, :city}
  ]

  # {autor, legenda, título no vídeo, público, horas atrás, curtidas, fundo}
  @shorts [
    {"bia.santos", "Os três tipos de pessoa no ônibus. Qual é você?",
     "3 tipos de pessoa no ônibus", [:humor], 1, 44, :warm},
    {"joao.pereira", "Gol de bicicleta na várzea de domingo.", "Gol de bicicleta na várzea",
     [:futebol], 3, 46, :green},
    {"maria.silva", "Pão de queijo em 30 segundos, sem enrolação.",
     "Pão de queijo em 30 segundos", [:cozinha], 6, 40, :warm},
    {"ana.costa", "Como o rio respira ao longo do dia.", "Como o rio respira", [:ciencia], 9, 30,
     :life},
    {"dona.rosa", "Bastidor da fornada das 6h.", "Bastidor da fornada", [:cozinha], 4, 18,
     :night},
    {"bia.santos", "Testei o acarajé de cinco barracas diferentes.", "Testei 5 acarajés",
     [:cozinha, :humor], 11, 41, :warm},
    {"carlos.souza", "O riff de violão de hoje.", "Riff do dia", [:musica], 13, 22, :cool},
    {"lucas.lima", "Golpe do falso suporte técnico: como reconhecer em 20 segundos.",
     "Golpe do falso suporte", [:ciencia], 15, 38, :cool},
    {"joao.pereira", "Os cinco tipos de narrador de futebol.", "5 tipos de narrador",
     [:futebol, :humor], 19, 45, :night},
    {"bia.santos", "Quando a tia descobre o grupo da família.", "Quando a tia descobre o grupo",
     [:humor], 27, 46, :warm},
    {"bia.santos", "Pôr do sol de dez segundos.", "Pôr do sol em 10 segundos", [:humor], 33, 37,
     :night},
    {"joao.pereira", "Treino de goleiro de várzea.", "Treino de goleiro", [:futebol], 40, 35,
     :green},
    {"carlos.souza", "Samba em 15 segundos.", "Samba em 15 segundos", [:musica], 45, 26, :fractal}
  ]

  # {autor, legenda, título no vídeo, público, horas atrás, curtidas, fundo, pontos de anúncio}
  @videos [
    {"joao.pereira", "Análise do clássico: o que decidiu o jogo no segundo tempo.",
     "Análise do clássico", [:futebol], 5, 44, :fractal, ~w(start)},
    {"lucas.lima", "Como funciona o código aberto da -rede+social, em linguagem simples.",
     "Código aberto em linguagem simples", [:ciencia], 12, 35, :cool, ~w(start end)},
    {"ana.costa", "Expedição: um dia inteiro medindo o rio.", "Um dia medindo o rio", [:ciencia],
     23, 30, :green, []}
  ]

  @campaigns [
    %{
      advertiser: "Banco Horizonte",
      title: "Conta digital sem tarifa",
      body: "Abra sua conta em cinco minutos, direto pelo celular.",
      cta: "Conhecer",
      color: "#1d4ed8",
      scope: :national,
      hours_per_day: 10_000,
      cents_per_impression: 2,
      paid_cents: 45_000_000
    },
    %{
      advertiser: "Conecta Fibra",
      title: "Internet de fibra para todo o Brasil",
      body: "Planos a partir de 500 mega, com instalação grátis.",
      cta: "Ver planos",
      color: "#7c3aed",
      scope: :national,
      hours_per_day: 6_000,
      cents_per_impression: 2,
      paid_cents: 27_000_000
    },
    %{
      advertiser: "Padaria Dona Rosa",
      title: "Pão quentinho às 6h",
      body: "Francês, pão de leite e pão de linguiça saindo do forno todo dia.",
      cta: "Como chegar",
      color: "#b45309",
      scope: :regional,
      region: "Campinas/SP",
      hours_per_day: 40,
      cents_per_impression: 1,
      paid_cents: 30_000
    },
    %{
      advertiser: "Livraria Beira-Rio",
      title: "Livros usados a partir de R$ 5",
      body: "Clássicos e novidades no centro do Recife.",
      cta: "Ver endereço",
      color: "#0f766e",
      scope: :regional,
      region: "Recife/PE",
      hours_per_day: 30,
      cents_per_impression: 1,
      paid_cents: 22_000
    },
    %{
      advertiser: "Açaí da Ilha",
      title: "Açaí grosso do jeito paraense",
      body: "Com peixe frito ou com farinha, você escolhe.",
      cta: "Pedir agora",
      color: "#6b21a8",
      scope: :regional,
      region: "Belém/PA",
      hours_per_day: 25,
      cents_per_impression: 1,
      paid_cents: 18_000
    },
    %{
      advertiser: "Acarajé da Esquina",
      title: "O acarajé mais pedido do bairro",
      body: "Quentinho a partir das 16h, com vatapá e camarão.",
      cta: "Como chegar",
      color: "#c2410c",
      scope: :regional,
      region: "Salvador/BA",
      hours_per_day: 25,
      cents_per_impression: 1,
      paid_cents: 18_000
    },
    %{
      advertiser: "Bike Conserto Centro",
      title: "Sua bicicleta pronta no mesmo dia",
      body: "Revisão completa e peças com garantia.",
      cta: "Agendar",
      color: "#15803d",
      scope: :regional,
      region: "São Paulo/SP",
      hours_per_day: 20,
      cents_per_impression: 1,
      paid_cents: 15_000
    },
    %{
      advertiser: "Café do Cais",
      title: "Café passado na hora e chimarrão",
      body: "Na beira do Guaíba, com wifi e tomada para trabalhar.",
      cta: "Ver cardápio",
      color: "#78350f",
      scope: :regional,
      region: "Porto Alegre/RS",
      hours_per_day: 20,
      cents_per_impression: 1,
      paid_cents: 15_000
    }
  ]

  # Quem já recebe por PIX. O Carlos fica sem chave, para a demonstração
  # mostrar o cadastro dela no painel do criador.
  @pix_ready ~w(maria.silva joao.pereira bia.santos lucas.lima dona.rosa)

  def run do
    if Accounts.get_by_nickname("maria.silva") do
      Logger.info("Os dados de demonstração já existem. Nada a fazer.")
    else
      seed()
    end

    :ok
  end

  defp seed do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    personas = Map.new(@personas, &{&1.nickname, create_persona(&1)})
    crowd = create_crowd(Map.values(personas))

    for {nickname, followed} <- @follows, other <- followed do
      Social.toggle_follow(Map.fetch!(personas, nickname), Map.fetch!(personas, other))
    end

    texts =
      for {nickname, body, audience, hours, likes} <- @text_posts do
        post = insert_post(personas, nickname, %{kind: :text, body: body}, nil, hours, now)
        {post, likes, audience}
      end

    photos =
      for {nickname, caption, audience, hours, likes, scene} <- @photo_posts do
        media = Media.store_binary(Art.svg(scene), ".svg")
        attrs = %{kind: :photo, body: caption, alt_text: Map.get(@scene_alt, scene)}
        post = insert_post(personas, nickname, attrs, media, hours, now)
        {post, likes, audience}
      end

    posts = texts ++ photos ++ create_clips(personas, now)

    posts
    |> Enum.with_index()
    |> Enum.each(fn {{post, likes, audience}, index} ->
      engage(post, likes, audience_of(crowd, audience), index)
    end)

    engage_personas(personas, posts)
    create_reports(crowd, personas, now)

    # O primeiro retrato do grafo, para a conta do feed já sair com provas.
    {:ok, _snapshot} = RedeSocial.GraphCommitments.take_snapshot()

    campaigns = create_campaigns(personas)
    create_last_month(personas, crowd, posts, campaigns)

    # O relatório do trimestre passado, já publicado.
    {:ok, _report} = Quarterly.publish(Date.shift(Date.utc_today(), month: -3))

    Logger.info(
      "Dados de demonstração criados: #{map_size(personas)} pessoas e #{length(crowd)} contas de público."
    )
  end

  defp audience_of(crowd, audience) do
    for {account, group} <- crowd, group in audience, do: account
  end

  defp create_persona(persona) do
    cpf = CPF.generate_for_testing()

    {:ok, account} =
      Accounts.register_verified(
        %{
          nickname: persona.nickname,
          govbr_level: persona.level,
          age_band: Map.get(persona, :age_band, :adult),
          region: persona.region,
          bio: persona.bio
        },
        cpf
      )

    Social.add_monthly_views(account.id, Social.current_month(), persona.monthly_views)

    # O banco simulado conhece a chave PIX de cada pessoa de exemplo,
    # <apelido>@pix.demo, no CPF dela.
    Pix.Demo.register("#{persona.nickname}@pix.demo", cpf, persona.nickname)

    if persona.nickname in @pix_ready,
      do: {:ok, _key} = Payments.register_pix_key(account, "#{persona.nickname}@pix.demo")

    cond do
      persona[:moderator] ->
        {:ok, account} = Moderation.grant_moderator(account)
        account

      persona[:legal_officer] ->
        {:ok, account} = RedeSocial.Identification.grant_legal_officer(account)
        account

      true ->
        account
    end
  end

  # Duas denúncias para a fila da moderação ter o que mostrar: um golpe de
  # verdade, que deve sair, e uma denúncia de má-fé contra um post legítimo,
  # que deve ficar.
  defp create_reports(crowd, personas, now) do
    scammer = Map.fetch!(personas, "promo.relampago")
    reporters = crowd |> Enum.take(4) |> Enum.map(&elem(&1, 0))

    scam =
      %Post{author_id: scammer.id}
      |> Post.changeset(%{
        kind: :text,
        body: "PROMOÇÃO: mande o código que chegou por SMS e ganhe R$ 500 no PIX hoje!"
      })
      |> Repo.insert!()
      |> Ecto.Changeset.change(inserted_at: DateTime.add(now, -2 * 3600, :second))
      |> Repo.update!()
      |> Repo.preload(:author)

    for reporter <- Enum.take(reporters, 3), do: :ok = Moderation.report(reporter, scam, 6)

    lucas = Map.fetch!(personas, "lucas.lima")

    hearing =
      Repo.one!(
        from p in Post,
          where: p.author_id == ^lucas.id and like(p.body, "Audiência pública%"),
          preload: :author
      )

    :ok = Moderation.report(List.last(reporters), hearing, 3)
  end

  # As pessoas de exemplo chegam com um histórico de verdade: curtiram e
  # assistiram a parte do que é do gosto delas. Só parte, para sobrar o que os
  # vizinhos de gosto parecido têm a sugerir.
  defp engage_personas(personas, posts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    pairs =
      @personas
      |> Enum.with_index()
      |> Enum.flat_map(fn {persona, i} ->
        account = Map.fetch!(personas, persona.nickname)

        for {post, _likes, audience} <- posts,
            post.author_id != account.id,
            Enum.any?(audience, &(&1 in persona.tastes)),
            rem(post.id + i, 2) == 0,
            do: {account, post}
      end)

    Repo.insert_all(
      Like,
      Enum.map(pairs, fn {account, post} ->
        %{account_id: account.id, post_id: post.id, inserted_at: now}
      end)
    )

    Repo.insert_all(
      View,
      for {account, post} <- pairs, post.kind in [:short, :video] do
        %{post_id: post.id, viewer_id: account.id, watched_ms: 30_000, inserted_at: now}
      end
    )
  end

  defp create_crowd(personas) do
    # Cada nome aparece uma vez em cada grupo do público.
    nicknames =
      for {first, i} <- Enum.with_index(@first_names),
          {group, offset} <- Enum.with_index(@audiences),
          do: {"#{first}.#{Enum.at(@last_names, rem(i + offset, 10))}", group}

    nicknames
    |> Enum.with_index()
    |> Enum.map(fn {{nickname, group}, i} ->
      {:ok, account} =
        Accounts.register_verified(
          %{
            nickname: nickname,
            govbr_level: :bronze,
            age_band: :adult,
            region: Enum.at(@regions, rem(i, length(@regions)))
          },
          CPF.generate_for_testing()
        )

      Social.toggle_follow(account, Enum.at(personas, rem(i, length(personas))))
      Social.toggle_follow(account, Enum.at(personas, rem(i + 3, length(personas))))
      {account, group}
    end)
  end

  # `media` é o endereço de uma foto ou os campos de um vídeo já convertido
  # (Media.ingest_now/2).
  defp insert_post(personas, nickname, attrs, media, hours_ago, now) do
    author = Map.fetch!(personas, nickname)

    attrs =
      if Accounts.can_monetize?(author),
        do: attrs,
        else: Map.merge(attrs, %{monetized: false, ad_markers: []})

    post =
      case media do
        %{} = fields -> struct(%Post{author_id: author.id}, Map.delete(fields, :kind))
        path -> %Post{author_id: author.id, media_path: path}
      end
      |> Post.changeset(attrs)
      |> Repo.insert!()

    created_at = DateTime.add(now, -hours_ago * 3600 - :rand.uniform(1800), :second)

    post
    |> Ecto.Changeset.change(inserted_at: created_at, updated_at: created_at)
    |> Repo.update!()
  end

  defp create_clips(personas, now) do
    if Clips.available?() do
      shorts =
        Task.async_stream(
          @shorts,
          fn {nickname, caption, title, audience, hours, likes, style} ->
            media = render(personas, nickname, title, style, 8, {480, 854}, caption)
            attrs = %{kind: :short, body: caption, monetized: true}
            {insert_post(personas, nickname, attrs, media, hours, now), likes, audience}
          end,
          max_concurrency: 4,
          timeout: :infinity
        )

      videos =
        Task.async_stream(
          @videos,
          fn {nickname, caption, title, audience, hours, likes, style, markers} ->
            media = render(personas, nickname, title, style, 20, {854, 480}, caption)
            attrs = %{kind: :video, body: caption, ad_markers: markers}
            {insert_post(personas, nickname, attrs, media, hours, now), likes, audience}
          end,
          max_concurrency: 2,
          timeout: :infinity
        )

      Enum.map(Enum.to_list(shorts) ++ Enum.to_list(videos), fn {:ok, result} -> result end)
    else
      Logger.warning("ffmpeg não encontrado: a demonstração vai subir sem shorts e vídeos.")
      []
    end
  end

  # Gera o clipe e converte em HLS na hora, pelo mesmo caminho dos vídeos
  # enviados, sem passar pela fila.
  defp render(personas, nickname, title, style, seconds, size, narration) do
    {:ok, path} = Clips.render(title, style, seconds, size, narration)
    {:ok, fields} = Media.ingest_now(Map.fetch!(personas, nickname).id, path)
    fields
  end

  # Curtidas, salvamentos e views do público do post. Cada post começa num
  # ponto diferente da lista, para o público não ser sempre o mesmo.
  defp engage(_post, _likes, [], _index), do: :ok

  defp engage(post, likes, pool, index) do
    pool = Enum.reject(pool, &(&1.id == post.author_id))
    start = rem(index * 7, length(pool))
    rotated = Enum.drop(pool, start) ++ Enum.take(pool, start)
    likers = Enum.take(rotated, min(likes, length(rotated)))
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(
      Like,
      Enum.map(likers, &%{account_id: &1.id, post_id: post.id, inserted_at: now})
    )

    Repo.insert_all(
      Save,
      likers
      |> Enum.take(div(length(likers), 4))
      |> Enum.map(&%{account_id: &1.id, post_id: post.id, inserted_at: now})
    )

    if post.kind in [:short, :video] do
      views =
        for i <- 0..(length(likers) * 3 - 1)//1 do
          viewer = Enum.at(rotated, rem(i, length(rotated)))
          %{post_id: post.id, viewer_id: viewer.id, watched_ms: 15_000, inserted_at: now}
        end

      Repo.insert_all(View, views)
    end
  end

  # Cada campanha tem a empresa por trás, com CNPJ. A da Padaria Dona Rosa é
  # da conta dona.rosa, para a demonstração mostrar o lado de quem anuncia.
  # Elas começaram no mês passado, para o mês passado ter o que fechar.
  defp create_campaigns(personas) do
    today = Date.utc_today()
    now = DateTime.truncate(DateTime.utc_now(), :second)
    starts = today |> Date.beginning_of_month() |> Date.shift(month: -1)

    Enum.map(@campaigns, fn campaign ->
      owner = if campaign.advertiser == "Padaria Dona Rosa", do: Map.fetch!(personas, "dona.rosa")

      advertiser =
        Repo.insert!(%Advertiser{
          account_id: owner && owner.id,
          cnpj: CNPJ.generate_for_testing(),
          name: campaign.advertiser
        })

      Repo.insert!(
        struct(
          Campaign,
          Map.merge(campaign, %{
            advertiser_id: advertiser.id,
            status: :active,
            impressions_per_day: div(campaign.hours_per_day * 3600, 15),
            price_cents: campaign.paid_cents,
            paid_at: now,
            starts_on: starts,
            ends_on: Date.add(today, 20)
          })
        )
      )
    end)
  end

  # O mês passado, já fechado: anúncios que passaram nos vídeos (com algumas
  # views que o antifraude descarta), anúncios nos shorts e o fechamento,
  # com os extratos e os repasses por PIX.
  defp create_last_month(personas, crowd, posts, campaigns) do
    month = Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: -1)
    days = Date.days_in_month(month)
    viewers = Enum.map(crowd, &elem(&1, 0))
    authors = Map.new(Map.values(personas), &{&1.id, &1})
    national = Enum.filter(campaigns, &(&1.scope == :national))
    rosa = Enum.find(campaigns, &(&1.advertiser == "Padaria Dona Rosa"))

    at = fn day, hour ->
      DateTime.new!(Date.add(month, day - 1), Time.new!(rem(hour, 24), 0, 0), "Etc/UTC")
    end

    videos =
      for {%Post{kind: :video} = post, _likes, _audience} <- posts,
          post.monetized and Accounts.can_monetize?(Map.fetch!(authors, post.author_id)),
          do: post

    # Cada pessoa do público vê o anúncio uma vez por dia, em dias diferentes
    # para cada vídeo. Quem é de Campinas às vezes vê o anúncio da padaria.
    rows =
      for {post, n} <- Enum.with_index(videos),
          {viewer, i} <- Enum.with_index(viewers),
          day <- 1..days,
          rem(i + day, n + 1) == 0 do
        regional = viewer.region == "Campinas/SP" and rem(day, 3) == 0
        campaign = if regional, do: rosa, else: Enum.at(national, rem(i + day, length(national)))

        %{
          campaign_id: campaign.id,
          post_id: post.id,
          creator_id: post.author_id,
          viewer_id: viewer.id,
          viewer_region: viewer.region,
          viewer_verified: true,
          regional: regional,
          moment: "start",
          revenue_cents: campaign.cents_per_impression,
          inserted_at: at.(day, 12 + rem(i, 10))
        }
      end

    # O que o antifraude descarta: a mesma pessoa vendo o mesmo vídeo de novo
    # no mesmo dia, e views de uma conta básica, sem gov.br.
    {:ok, basic} = Accounts.register_basic(%{nickname: "sem.govbr", region: "São Paulo/SP"})
    target = List.first(videos)
    campaign = List.first(national)

    extra =
      for(i <- 0..19, do: {Enum.at(viewers, i), true, at.(5, 12 + rem(i, 10) + 1)}) ++
        for(day <- 1..15, do: {basic, false, at.(day, 20)})

    discarded =
      Enum.map(extra, fn {viewer, verified, when_} ->
        %{
          campaign_id: campaign.id,
          post_id: target.id,
          creator_id: target.author_id,
          viewer_id: viewer.id,
          viewer_region: viewer.region,
          viewer_verified: verified,
          regional: false,
          moment: "start",
          revenue_cents: campaign.cents_per_impression,
          inserted_at: when_
        }
      end)

    (rows ++ discarded) |> Enum.chunk_every(2_000) |> Enum.each(&Repo.insert_all(AdView, &1))

    # Anúncios nos shorts, com o rateio feito pelo motor na hora.
    shorts = for {%Post{kind: :short} = post, _likes, _audience} <- posts, do: post

    for n <- 0..59 do
      block = for k <- 0..5, do: Enum.at(shorts, rem(n + k, length(shorts)))

      watched =
        Enum.map(
          block,
          &%{"post_id" => &1.id, "watched_ms" => 3_000 + rem(n * 7 + &1.id * 13, 9_000)}
        )

      viewer = Enum.at(viewers, rem(n * 3, length(viewers)))
      campaign = Enum.at(national, rem(n, length(national)))
      {:ok, impression} = Ads.record_impression(viewer, campaign.id, watched)

      Repo.update_all(from(i in RedeSocial.Ads.Impression, where: i.id == ^impression.id),
        set: [inserted_at: at.(rem(n, days) + 1, 18)]
      )
    end

    {:ok, _month, _payouts} = Payments.close_month(month)
  end
end
