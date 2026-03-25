defmodule KithWeb.OAuthController do
  @moduledoc """
  Handles OAuth redirect and callback for social login providers (GitHub, Google).

  Routes:
    GET /auth/:provider          — redirect to provider
    GET /auth/:provider/callback — handle callback
  """

  use KithWeb, :controller

  alias Kith.Accounts
  alias KithWeb.UserAuth

  @supported_providers ~w(github google)

  def request(conn, %{"provider" => provider}) when provider in @supported_providers do
    case Accounts.oauth_provider_config(provider) do
      {:ok, config} ->
        config = put_redirect_uri(config, conn, provider)

        case strategy_module(provider).authorize_url(config) do
          {:ok, %{url: url, session_params: session_params}} ->
            conn
            |> put_session(:oauth_session_params, session_params)
            |> put_session(:oauth_provider, provider)
            |> redirect(external: url)

          {:ok, %{url: url}} ->
            conn
            |> put_session(:oauth_provider, provider)
            |> redirect(external: url)

          {:error, _error} ->
            conn
            |> put_flash(:error, "Failed to start OAuth flow.")
            |> redirect(to: ~p"/users/log-in")
        end

      {:error, :unknown_provider} ->
        conn
        |> put_flash(:error, "OAuth provider not configured.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def request(conn, %{"provider" => _}) do
    conn
    |> put_flash(:error, "Unsupported OAuth provider.")
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(conn, %{"provider" => provider} = params) when provider in @supported_providers do
    session_params = get_session(conn, :oauth_session_params) || %{}

    case Accounts.oauth_provider_config(provider) do
      {:ok, config} ->
        config =
          config
          |> put_redirect_uri(conn, provider)
          |> Keyword.put(:session_params, session_params)

        case strategy_module(provider).callback(config, params) do
          {:ok, %{user: user_info, token: token}} ->
            handle_oauth_result(conn, provider, user_info, token)

          {:ok, %{user: user_info}} ->
            handle_oauth_result(conn, provider, user_info, %{})

          {:error, _error} ->
            conn
            |> delete_session(:oauth_session_params)
            |> delete_session(:oauth_provider)
            |> put_flash(:error, "OAuth authentication failed.")
            |> redirect(to: ~p"/users/log-in")
        end

      {:error, :unknown_provider} ->
        conn
        |> put_flash(:error, "OAuth provider not configured.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, %{"provider" => _}) do
    conn
    |> put_flash(:error, "Unsupported OAuth provider.")
    |> redirect(to: ~p"/users/log-in")
  end

  # ── Private ───────────────────────────────────────────────────────

  defp handle_oauth_result(conn, provider, user_info, token) do
    uid = to_string(user_info["sub"])
    email = user_info["email"]
    token_attrs = Accounts.extract_token_attrs(token)

    conn =
      conn
      |> delete_session(:oauth_session_params)
      |> delete_session(:oauth_provider)

    identity = Accounts.get_identity_by_provider_uid(provider, uid)
    current_user = conn.assigns[:current_scope] && conn.assigns.current_scope.user
    existing_user = is_binary(email) && Accounts.get_user_by_email(email)

    oauth_context = %{
      identity: identity,
      current_user: current_user,
      existing_user: existing_user,
      email: email
    }

    dispatch_oauth_result(conn, provider, uid, token_attrs, user_info, oauth_context)
  end

  defp dispatch_oauth_result(conn, provider, uid, token_attrs, _user_info, %{identity: identity})
       when not is_nil(identity) do
    Accounts.upsert_identity(identity.user, provider, uid, token_attrs)

    conn
    |> put_flash(:info, "Welcome back!")
    |> UserAuth.log_in_user(identity.user, %{"remember_me" => "false"})
  end

  defp dispatch_oauth_result(conn, provider, uid, token_attrs, _user_info, %{
         current_user: current_user
       })
       when not is_nil(current_user) do
    link_identity_to_current_user(conn, provider, uid, token_attrs, current_user)
  end

  defp dispatch_oauth_result(conn, provider, uid, token_attrs, _user_info, %{
         existing_user: existing_user
       })
       when not is_nil(existing_user) and existing_user != false do
    link_identity_to_existing_user(conn, provider, uid, token_attrs, existing_user)
  end

  defp dispatch_oauth_result(conn, provider, uid, _token_attrs, user_info, %{email: email}) do
    register_new_oauth_user(conn, provider, uid, user_info, email)
  end

  defp link_identity_to_current_user(conn, provider, uid, token_attrs, current_user) do
    case Accounts.upsert_identity(current_user, provider, uid, token_attrs) do
      {:ok, _identity} ->
        conn
        |> put_flash(:info, "#{String.capitalize(provider)} account linked.")
        |> redirect(to: ~p"/users/settings")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to link #{provider} account.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp link_identity_to_existing_user(conn, provider, uid, token_attrs, existing_user) do
    case Accounts.upsert_identity(existing_user, provider, uid, token_attrs) do
      {:ok, _identity} ->
        conn
        |> put_flash(:info, "Welcome back! #{String.capitalize(provider)} account linked.")
        |> UserAuth.log_in_user(existing_user, %{"remember_me" => "false"})

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to link account.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp register_new_oauth_user(conn, provider, uid, user_info, email) do
    cond do
      Application.get_env(:kith, :disable_signup, false) ->
        conn
        |> put_flash(:error, "Registration is currently disabled.")
        |> redirect(to: ~p"/users/log-in")

      is_binary(email) ->
        token_attrs = Accounts.extract_token_attrs(%{})

        case Accounts.register_oauth_user(provider, uid, user_info, token_attrs) do
          {:ok, user} ->
            conn
            |> put_flash(:info, "Account created successfully!")
            |> UserAuth.log_in_user(user, %{"remember_me" => "false"})

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to create account.")
            |> redirect(to: ~p"/users/log-in")
        end

      true ->
        conn
        |> put_flash(:error, "No email address provided by #{provider}.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp strategy_module("github"), do: Assent.Strategy.Github
  defp strategy_module("google"), do: Assent.Strategy.Google

  defp put_redirect_uri(config, conn, provider) do
    Keyword.put(config, :redirect_uri, url(conn, ~p"/auth/#{provider}/callback"))
  end
end
