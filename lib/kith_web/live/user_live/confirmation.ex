defmodule KithWeb.UserLive.Confirmation do
  use KithWeb, :live_view

  alias Kith.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>Confirm your account</.header>
        </div>

        <.form for={@form} id="confirmation_form" phx-submit="confirm">
          <input type="hidden" name="token" value={@token} />
          <.button class="btn btn-primary w-full" phx-disable-with="Confirming...">
            Confirm my account
          </.button>
        </.form>

        <p class="text-center mt-4 text-sm text-zinc-600">
          <.link navigate={~p"/users/log-in"} class="text-brand hover:underline">
            Back to log in
          </.link>
        </p>
      </div>
    </Layouts.app>
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
