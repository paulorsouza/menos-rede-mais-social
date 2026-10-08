defmodule RedeSocialWeb.Router do
  use RedeSocialWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", RedeSocialWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end
end
