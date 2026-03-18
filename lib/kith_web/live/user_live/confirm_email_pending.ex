defmodule KithWeb.UserLive.ConfirmEmailPending do
  use KithWeb, :live_view

  alias Kith.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm text-center space-y-6">
        <.header>
          Check your email
          <:subtitle>
            We sent a verification link to <strong>{@current_scope.user.email}</strong>.
            Please click the link to verify your account.
          </:subtitle>
        </.header>

        <p class="text-sm text-zinc-600">
          Didn't receive the email? Check your spam folder, or click below to resend.
        </p>

        <.button phx-click="resend" phx-disable-with="Sending..." class="btn btn-primary w-full">
          Resend verification email
        </.button>

        <p class="text-sm text-zinc-500 mt-4">
          <.link href={~p"/users/log-out"} method="delete" class="text-brand hover:underline">
            Log out
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if user.confirmed_at do
      {:ok, redirect(socket, to: ~p"/")}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("resend", _params, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.deliver_user_confirmation_instructions(
           user,
           &url(~p"/users/confirm/#{&1}")
         ) do
      {:ok, _email} ->
        {:noreply, put_flash(socket, :info, "Verification email sent. Please check your inbox.")}

      {:error, :already_confirmed} ->
        {:noreply, redirect(socket, to: ~p"/")}
    end
  end
end
