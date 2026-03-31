defmodule KithWeb.UserLive.ConfirmEmailPending do
  use KithWeb, :live_view

  require Logger

  alias Kith.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="text-center space-y-6">
        <div>
          <div class="flex justify-center mb-4">
            <div class="flex items-center justify-center size-14 rounded-full bg-[var(--color-accent-subtle)]">
              <.icon name="hero-envelope" class="size-7 text-[var(--color-accent)]" />
            </div>
          </div>

          <h1 class="text-xl font-semibold text-[var(--color-text-primary)]">Check your email</h1>

          <p class="mt-2 text-sm text-[var(--color-text-secondary)] leading-relaxed">
            We sent a verification link to <strong class="text-[var(--color-text-primary)]">{@current_scope.user.email}</strong>.
            Please click the link to verify your account.
          </p>
        </div>

        <p class="text-sm text-[var(--color-text-tertiary)]">
          Didn't receive the email? Check your spam folder, or click below to resend.
        </p>

        <UI.button phx-click="resend" phx-disable-with="Sending..." class="w-full">
          Resend verification email
        </UI.button>
        <p class="text-sm text-[var(--color-text-tertiary)]">
          <.link
            href={~p"/users/log-out"}
            method="delete"
            class="font-medium text-[var(--color-accent)] hover:text-[var(--color-accent-hover)] transition-colors"
          >
            Log out
          </.link>
        </p>
      </div>
    </Layouts.auth>
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

      {:error, reason} ->
        Logger.error("Failed to deliver confirmation email",
          user_id: socket.assigns.current_scope.user.id,
          error: inspect(reason)
        )

        {:noreply,
         put_flash(
           socket,
           :error,
           "Failed to send verification email. Please try again later."
         )}
    end
  end
end
