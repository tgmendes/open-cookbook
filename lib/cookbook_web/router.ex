defmodule CookbookWeb.Router do
  use CookbookWeb, :router

  import CookbookWeb.Auth, only: [fetch_current_user: 2, require_authenticated_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CookbookWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check (no auth, no browser pipeline)
  scope "/", CookbookWeb do
    pipe_through :api
    get "/health", HealthController, :index
  end

  # Public routes (no auth required)
  scope "/", CookbookWeb do
    pipe_through :browser

    live "/login", LoginLive, :index
    get "/auth/callback", AuthController, :callback
    get "/auth/logout", AuthController, :logout
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
      live "/planner", PlannerLive, :index
      live "/planner/shopping", ShoppingListLive, :index
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
