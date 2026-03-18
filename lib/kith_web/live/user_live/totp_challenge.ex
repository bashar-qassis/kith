defmodule KithWeb.UserLive.TotpChallenge do
  use KithWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Two-factor authentication
            <:subtitle>Enter the 6-digit code from your authenticator app.</:subtitle>
          </.header>
        </div>

        <.form for={@form} id="totp_challenge_form" action={~p"/users/totp-verify"} method="post">
          <input type="hidden" name="totp_token" value={@totp_token} />
          <input type="hidden" name="remember_me" value={to_string(@remember_me)} />
          <.input
            field={@form[:code]}
            type="text"
            label="Authentication code"
            inputmode="numeric"
            pattern="[0-9a-zA-Z\-]{6,9}"
            autocomplete="one-time-code"
            maxlength="9"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full" phx-disable-with="Verifying...">
            Verify
          </.button>
        </.form>

        <p class="text-center text-sm text-zinc-500">
          Use a recovery code instead (enter it in the code field above, format: XXXX-XXXX)
        </p>

        <p class="text-center text-sm text-zinc-500">
          <.link navigate={~p"/users/log-in"} class="text-brand hover:underline">
            Back to log in
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    totp_token = session["totp_token"]
    remember_me = session["remember_me"] || false

    if totp_token do
      {:ok,
       assign(socket,
         totp_token: totp_token,
         remember_me: remember_me,
         form: to_form(%{"code" => ""}, as: "totp")
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Please log in first.")
       |> redirect(to: ~p"/users/log-in")}
    end
  end
end
