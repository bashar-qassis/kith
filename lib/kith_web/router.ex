defmodule KithWeb.Router do
  use KithWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KithWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check — no auth required
  scope "/", KithWeb do
    get "/health", HealthController, :index
  end

  scope "/", KithWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # API scope — Bearer token auth, no CSRF
  scope "/api", KithWeb.API do
    pipe_through :api
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:kith, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KithWeb.Telemetry
    end
  end
end
