defmodule KithWeb.Router do
  use KithWeb, :router

  import KithWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KithWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Browser-based JSON API (needs session for challenge storage, but returns JSON)
  pipeline :browser_json do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # Health check — no auth required
  scope "/", KithWeb do
    get "/health", HealthController, :index
  end

  scope "/", KithWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  pipeline :api_public_rate_limited do
    plug :accepts, ["json"]
    plug KithWeb.Plugs.RateLimiter, limit: 20, period: 60_000, key_prefix: "api_auth_token"
  end

  # API token creation (public — no bearer token needed, rate-limited)
  scope "/api", KithWeb.API do
    pipe_through [:api_public_rate_limited]

    post "/auth/token", AuthController, :create
  end

  # API scope — Bearer token auth, per-account rate limiting
  scope "/api", KithWeb.API do
    pipe_through [:api, KithWeb.Plugs.FetchApiUser, KithWeb.Plugs.ApiRateLimiter]

    delete "/auth/token", AuthController, :delete_current
    delete "/auth/token/:id", AuthController, :delete
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:kith, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KithWeb.Telemetry
    end
  end

  ## Authentication routes

  # Authenticated routes that do NOT require confirmed email
  scope "/", KithWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated_unconfirmed,
      on_mount: [{KithWeb.UserAuth, :require_authenticated}] do
      live "/users/confirm-email", UserLive.ConfirmEmailPending, :new
    end
  end

  # Authenticated routes — require logged-in + confirmed user
  scope "/", KithWeb do
    pipe_through [:browser, :require_authenticated_user, :require_confirmed_user]

    live_session :require_authenticated_user,
      on_mount: [{KithWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/users/totp-setup", UserLive.TotpSetup, :new
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # WebAuthn registration (authenticated, JSON over session)
  scope "/auth/webauthn", KithWeb do
    pipe_through [:browser_json, :require_authenticated_user]

    post "/register/challenge", WebauthnController, :register_challenge
    post "/register/complete", WebauthnController, :register_complete
    get "/credentials", WebauthnController, :list_credentials
    delete "/credentials/:id", WebauthnController, :delete_credential
  end

  # WebAuthn authentication (public, JSON over session)
  scope "/auth/webauthn", KithWeb do
    pipe_through [:browser_json]

    post "/authenticate/challenge", WebauthnController, :authenticate_challenge
    post "/authenticate/complete", WebauthnController, :authenticate_complete
  end

  # OAuth routes (browser-based, public)
  scope "/auth", KithWeb do
    pipe_through [:browser]

    get "/:provider", OAuthController, :request
    get "/:provider/callback", OAuthController, :callback
  end

  # Public auth routes — may or may not be logged in
  scope "/", KithWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{KithWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/confirm/:token", UserLive.Confirmation, :new
      live "/users/reset-password", UserLive.ForgotPassword, :new
      live "/users/reset-password/:token", UserLive.ResetPassword, :new
      live "/users/two-factor", UserLive.TotpChallenge, :new
    end

    post "/users/log-in", UserSessionController, :create
    post "/users/totp-verify", UserSessionController, :totp_verify
    delete "/users/log-out", UserSessionController, :delete
  end
end
