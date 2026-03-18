defmodule KithWeb.UserLive.ResetPassword do
  use KithWeb, :live_view

  alias Kith.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>Reset password</.header>
        </div>

        <.form for={@form} id="reset_password_form" phx-submit="reset" phx-change="validate">
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
          />
          <.button class="btn btn-primary w-full" phx-disable-with="Resetting...">
            Reset password
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
    if user = Accounts.get_user_by_reset_password_token(token) do
      changeset = Accounts.change_user_password(user, %{}, hash_password: false)

      {:ok,
       assign(socket,
         user: user,
         token: token,
         form: to_form(changeset, as: "user")
       ), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Reset password link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/reset-password")}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  def handle_event("reset", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully. You may now log in.")
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end
end
