defmodule KithWeb.UserLive.TotpSetup do
  use KithWeb, :live_view

  alias Kith.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-6">
        <%= if @recovery_codes do %>
          <div class="text-center">
            <.header>
              Two-factor authentication enabled
              <:subtitle>
                Store these recovery codes somewhere safe. You won't be able to see them again.
              </:subtitle>
            </.header>
          </div>
          
          <div
            class="bg-base-200 rounded-lg p-4 font-mono text-sm grid grid-cols-2 gap-2"
          >
            <div :for={code <- @recovery_codes} class="text-center py-1">{code}</div>
          </div>
          
          <div
            class="flex gap-2"
            x-data={"recoveryCodes(#{Jason.encode!(@recovery_codes)})"}
          >
            <button
              type="button"
              class="btn btn-outline flex-1 gap-2"
              x-on:click="copyAll"
            >
              <span x-show="!copied">Copy all</span> <span x-show="copied" x-cloak>Copied!</span>
            </button>
            <button
              type="button"
              class="btn btn-outline flex-1 gap-2"
              x-on:click="downloadTxt"
            >
              Download as .txt
            </button>
          </div>
          
          <.link navigate={~p"/users/settings"} class="btn btn-primary w-full">
            I've saved my recovery codes
          </.link>
        <% else %>
          <div class="text-center">
            <.header>
              Set up two-factor authentication
              <:subtitle>
                Scan the QR code with your authenticator app, then enter the 6-digit code to confirm.
              </:subtitle>
            </.header>
          </div>
          
          <div class="flex justify-center">
            <img src={@qr_data_url} alt="TOTP QR Code" class="rounded-lg" />
          </div>
          
          <details class="text-sm text-zinc-600">
            <summary class="cursor-pointer text-brand hover:underline">
              Can't scan? Enter this code manually
            </summary>
            
            <code class="block mt-2 p-2 bg-base-200 rounded text-center font-mono tracking-widest">
              {@secret}
            </code>
          </details>
          
          <.form for={@form} id="totp_confirm_form" phx-submit="confirm">
            <.input
              field={@form[:code]}
              type="text"
              label="6-digit code"
              inputmode="numeric"
              pattern="[0-9]{6}"
              autocomplete="one-time-code"
              maxlength="6"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="btn btn-primary w-full" phx-disable-with="Verifying...">
              Enable two-factor authentication
            </.button>
          </.form>
          
          <p class="text-center text-sm text-zinc-500">
            <.link navigate={~p"/users/settings"} class="text-brand hover:underline">Cancel</.link>
          </p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if user.totp_enabled do
      {:ok,
       socket
       |> put_flash(:info, "Two-factor authentication is already enabled.")
       |> redirect(to: ~p"/users/settings")}
    else
      secret = Accounts.generate_totp_secret()
      uri = Accounts.totp_uri(secret, user.email)
      qr_data_url = Accounts.totp_qr_code_data_url(uri)

      {:ok,
       assign(socket,
         secret: secret,
         qr_data_url: qr_data_url,
         recovery_codes: nil,
         form: to_form(%{"code" => ""}, as: "totp")
       )}
    end
  end

  @impl true
  def handle_event("confirm", %{"totp" => %{"code" => code}}, socket) do
    user = socket.assigns.current_scope.user
    secret = socket.assigns.secret

    case Accounts.enable_totp(user, secret, code) do
      {:ok, {_user, raw_codes}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Two-factor authentication has been enabled.")
         |> assign(recovery_codes: raw_codes)}

      {:error, :invalid_code} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid code. Please try again.")
         |> assign(form: to_form(%{"code" => ""}, as: "totp"))}
    end
  end
end
