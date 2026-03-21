defmodule KithWeb.UserLive.Confirmation do
  use KithWeb, :live_view

  alias Kith.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="space-y-6">
        <div class="text-center">
          <h1 class="text-xl font-semibold text-[var(--color-text-primary)]">Confirm your account</h1>
        </div>

        <.form for={@form} id="confirmation_form" phx-submit="confirm">
          <input type="hidden" name="token" value={@token} />
          <UI.button class="w-full" phx-disable-with="Confirming...">
            Confirm my account
          </UI.button>
        </.form>

        <p class="text-center text-sm text-[var(--color-text-secondary)]">
          <.link
            navigate={~p"/users/log-in"}
            class="font-medium text-[var(--color-accent)] hover:text-[var(--color-accent-hover)] transition-colors"
          >
            Back to log in
          </.link>
        </p>
      </div>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    form = to_form(%{}, as: "user")
    {:ok, assign(socket, token: token, form: form), temporary_assigns: [form: nil]}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> put_flash(:error, "Confirmation link is invalid or it has expired.")
     |> push_navigate(to: ~p"/users/log-in")}
  end

  @impl true
  def handle_event("confirm", %{"token" => token}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account confirmed successfully. You may now log in.")
         |> push_navigate(to: ~p"/users/log-in")}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Confirmation link is invalid or it has expired.")
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end
end
