defmodule CookbookWeb.Router do
  use CookbookWeb, :router

  import CookbookWeb.Auth,
    only: [fetch_current_user: 2, require_authenticated_user: 2, no_store: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CookbookWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug :no_store
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug CookbookWeb.ApiAuth
  end

  scope "/api/v1", CookbookWeb do
    pipe_through [:api, :authenticated_api]
    get "/profile", CookbookApiController, :profile
    get "/recipes", CookbookApiController, :index
    post "/recipes", CookbookApiController, :create
    get "/recipes/:id", CookbookApiController, :show
    patch "/recipes/:id", CookbookApiController, :update
    delete "/recipes/:id", CookbookApiController, :delete
    get "/meal-plans/:week", CookbookApiController, :plan
    put "/meal-plans/:week/slots/:day/:meal", CookbookApiController, :replace_slot
    get "/shopping-lists/:week", CookbookApiController, :shopping
  end

  # Health check (no auth, no browser pipeline)
  scope "/", CookbookWeb do
    pipe_through :api
    get "/health", HealthController, :index
    get "/api/openapi.json", OpenAPIController, :show
  end

  # Public routes (no auth required)
  scope "/", CookbookWeb do
    pipe_through :browser

    live "/login", LoginLive, :index
    get "/auth/callback", AuthController, :callback
    delete "/auth/logout", AuthController, :logout
  end

  # Authenticated routes
  scope "/", CookbookWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated, on_mount: {CookbookWeb.Auth, :require_auth} do
      live "/", DashboardLive, :index
      live "/recipes", RecipeListLive, :index
      live "/recipes/new", RecipeFormLive, :new
      live "/recipes/:id", RecipeShowLive, :show
      live "/recipes/:id/edit", RecipeFormLive, :edit
      live "/recipes/:id/cook", CookModeLive, :cook
      live "/planner", PlannerLive, :index
      live "/planner/shopping", ShoppingListLive, :index
      live "/settings/connections", ApiTokenLive, :index
      live "/settings", SettingsLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:cookbook, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CookbookWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
