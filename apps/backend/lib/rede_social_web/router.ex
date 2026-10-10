defmodule RedeSocialWeb.Router do
  use RedeSocialWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug RedeSocialWeb.Auth, :fetch_current_account
  end

  # Ida e volta do gov.br: é navegação do navegador, não chamada JSON.
  pipeline :browser_redirect do
    plug :fetch_session
  end

  pipeline :authenticated do
    plug RedeSocialWeb.Auth, :require_account
  end

  pipeline :moderator do
    plug RedeSocialWeb.Auth, :require_moderator
  end

  pipeline :legal do
    plug RedeSocialWeb.Auth, :require_legal_officer
  end

  pipeline :demo do
    plug RedeSocialWeb.Auth, :require_demo_mode
  end

  scope "/api/govbr", RedeSocialWeb do
    pipe_through :browser_redirect

    get "/entrar", GovBrController, :start
    get "/retorno", GovBrController, :callback
  end

  scope "/api", RedeSocialWeb do
    pipe_through :api

    get "/govbr/status", GovBrController, :status
    post "/govbr/cadastro", GovBrController, :register

    get "/health", HealthController, :show
    options "/envios", UploadController, :options
    # Chamado pelo servidor de transmissão (infra/ao-vivo), não pelo app.
    post "/ao-vivo/autorizar", LiveController, :authorize
    get "/transparency", TransparencyController, :show
    get "/me", SessionController, :show
    delete "/session", SessionController, :delete
    get "/accounts/:nickname", AccountController, :show
    get "/posts/:id", PostController, :show
    get "/moderation/rules", ModerationController, :rules
    get "/registro", RegistroController, :index
    get "/registro/entradas", RegistroController, :entries
    get "/registro/prova/:index", RegistroController, :inclusion
    get "/registro/consistencia", RegistroController, :consistency

    # Só na demonstração: pessoas de exemplo e gov.br simulado.
    scope "/" do
      pipe_through :demo

      post "/session", SessionController, :create
      get "/demo/personas", DemoController, :personas
      get "/govbr-simulado/cpf-de-teste", DemoController, :test_cpf
      get "/demo/cnpj-de-teste", DemoController, :test_cnpj
      post "/demo/pix/:txid/pagar", DemoController, :pay_charge
      post "/govbr-simulado/cadastro", DemoController, :register
      post "/govbr-simulado/conta-basica", DemoController, :register_basic
    end

    scope "/" do
      pipe_through :authenticated

      get "/feed", FeedController, :index
      get "/feed/conta", FeedController, :account
      get "/shorts", FeedController, :shorts
      post "/posts", PostController, :create
      post "/envios", UploadController, :create
      post "/lives", LiveController, :create
      get "/envios/:id", UploadController, :show
      patch "/envios/:id", UploadController, :update
      delete "/envios/:id", UploadController, :delete
      post "/posts/:id/like", PostController, :like
      post "/posts/:id/save", PostController, :save
      post "/posts/:id/views", PostController, :view
      post "/posts/:id/report", PostController, :report
      post "/posts/:id/appeal", PostController, :appeal
      get "/me/notices", NoticeController, :index
      get "/me/export", PrivacyController, :export
      delete "/me", PrivacyController, :delete
      post "/me/notices/read", NoticeController, :read
      post "/accounts/:nickname/follow", AccountController, :follow
      post "/ads/impressions", AdController, :impression
      post "/ads/views", AdController, :view
      get "/creator/dashboard", CreatorController, :show
      post "/creator/pix", CreatorController, :pix
      get "/creator/statements/:month", CreatorController, :statement
      get "/creator/statements/:month/file", CreatorController, :statement_file
      get "/anunciante", AdvertiserController, :show
      post "/anunciante", AdvertiserController, :register
      post "/anunciante/orcamento", AdvertiserController, :price
      post "/anunciante/campanhas", AdvertiserController, :create

      scope "/identification" do
        pipe_through :legal

        get "/orders", IdentificationController, :index
        post "/orders", IdentificationController, :create
        get "/orders/:id/package", IdentificationController, :package
        post "/orders/:id/partials", IdentificationController, :submit
        post "/orders/:id/simulate/:guardian", IdentificationController, :simulate
        post "/orders/:id/open", IdentificationController, :open
      end

      scope "/moderation" do
        pipe_through :moderator

        get "/queue", ModerationController, :queue
        post "/posts/:id/remove", ModerationController, :remove
        post "/posts/:id/keep", ModerationController, :keep
        post "/appeals/:id/decide", ModerationController, :decide
        post "/campaigns/:id/approve", ModerationController, :approve_campaign
        post "/campaigns/:id/reject", ModerationController, :reject_campaign
      end
    end
  end
end
