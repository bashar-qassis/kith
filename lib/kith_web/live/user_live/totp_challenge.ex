defmodule KithWeb.UserLive.TotpChallenge do
  use KithWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        class="mx-auto max-w-sm space-y-4"
        x-data="{ recoveryMode: false }"
      >
        <div class="text-center">
          <.header>
            Two-factor authentication
            <:subtitle>
              <span x-show="!recoveryMode">Enter the 6-digit code from your authenticator app.</span>
              <span x-show="recoveryMode" x-cloak>
                Enter one of your recovery codes (format: XXXX-XXXX).
              </span>
            </:subtitle>
          </.header>
        </div>

        <form
          id="totp_challenge_form"
          action={~p"/users/totp-verify"}
          method="post"
          x-ref="totpForm"
        >
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <input type="hidden" name="totp_token" value={@totp_token} />
          <input type="hidden" name="remember_me" value={to_string(@remember_me)} />
          <div x-show="!recoveryMode">
            <div class="fieldset mb-2">
              <label for="totp_code">
                <span class="label mb-1">Authentication code</span>
                <input
                  type="text"
                  name="totp[code]"
                  id="totp_code"
                  inputmode="numeric"
                  pattern="[0-9]{6}"
                  autocomplete="one-time-code"
                  maxlength="6"
                  required
                  phx-mounted={JS.focus()}
                  class="w-full input"
                  x-on:input="if ($event.target.value.length === 6 && /^\d{6}$/.test($event.target.value)) { $nextTick(() => $refs.totpForm.submit()) }"
                />
              </label>
            </div>
          </div>

          <div x-show="recoveryMode" x-cloak>
            <.input
              field={@form[:code]}
              name="totp[code]"
              type="text"
              label="Recovery code"
              pattern="[0-9a-zA-Z\-]{9}"
              autocomplete="off"
              maxlength="9"
              placeholder="XXXX-XXXX"
              required
            />
          </div>
          <.button class="btn btn-primary w-full" phx-disable-with="Verifying...">Verify</.button>
        </form>

        <p class="text-center text-sm text-zinc-500">
          <button
            type="button"
            class="text-brand hover:underline"
            x-on:click="recoveryMode = !recoveryMode"
            x-text="recoveryMode ? 'Use authenticator code instead' : 'Use a recovery code instead'"
          >
          </button>
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
