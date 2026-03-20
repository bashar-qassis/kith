defmodule KithWeb.Plugs.AssignLocale do
  @moduledoc """
  Plug that reads locale from the current user's preferences (falling back to
  account locale, then "en"), sets Gettext and ex_cldr locales, and assigns
  `@locale` to the connection for use in templates.

  Must run **after** `fetch_current_scope_for_user` in the pipeline so it has
  access to user preferences.
  """

  import Plug.Conn

  @rtl_locales ~w(ar he fa ur)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = resolve_locale(conn)

    Gettext.put_locale(KithWeb.Gettext, locale)
    Kith.Cldr.put_locale(locale)

    conn
    |> assign(:locale, locale)
    |> assign(:html_dir, html_dir(locale))
  end

  defp resolve_locale(conn) do
    with %{current_scope: %{user: user}} when not is_nil(user) <- conn.assigns,
         locale when is_binary(locale) and locale != "" <- user.locale do
      locale
    else
      _ -> resolve_account_locale(conn)
    end
  end

  defp resolve_account_locale(conn) do
    with %{current_scope: %{account: account}} when not is_nil(account) <- conn.assigns,
         locale when is_binary(locale) and locale != "" <- account.locale do
      locale
    else
      _ -> "en"
    end
  end

  @doc """
  Returns `"rtl"` for RTL locales, `"ltr"` for all others.
  """
  @spec html_dir(String.t()) :: String.t()
  def html_dir(locale) do
    # Extract base language from locale (e.g., "ar-EG" -> "ar")
    base = locale |> String.split("-") |> List.first() |> String.downcase()

    if base in @rtl_locales, do: "rtl", else: "ltr"
  end
end
