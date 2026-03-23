defmodule KithWeb.UserLive.InvitationAcceptance do
  @moduledoc """
  Unauthenticated LiveView for accepting a team invitation.
  Route: GET /invitations/:token (in browser pipeline, no auth required).
  """

  use KithWeb, :live_view

  alias Kith.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Accept Invitation")
     |> assign(:invitation, nil)
     |> assign(:error, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_params(%{"token" => token}, _uri, socket) do
    case Accounts.get_invitation_by_token(token) do
      {:error, _} ->
        {:noreply,
         socket
         |> assign(:error, "This invitation has expired or has already been used.")
         |> assign(:token, token)}

      {:ok, invitation} ->
        changeset = Accounts.change_user_registration(%Kith.Accounts.User{})

        {:noreply,
         socket
         |> assign(:invitation, invitation)
         |> assign(:token, token)
         |> assign(:form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Accounts.change_user_registration(%Kith.Accounts.User{}, user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("accept", %{"user" => user_params}, socket) do
    token = socket.assigns.token

    case Accounts.accept_invitation(token, user_params) do
      {:ok, user} ->
        Kith.AuditLogs.log_event(user.account_id, user, :user_joined,
          metadata: %{email: user.email, role: user.role}
        )

        Kith.AuditLogs.log_event(user.account_id, user, :invitation_accepted,
          metadata: %{invitation_email: socket.assigns.invitation.email}
        )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Welcome to #{socket.assigns.invitation.account_name || "the team"}!"
         )
         |> redirect(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} when is_binary(reason) ->
        {:noreply,
         socket
         |> assign(:error, reason)
         |> assign(:invitation, nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <%= if @error do %>
        <div class="text-center space-y-5">
          <div class="flex justify-center">
            <div class="flex items-center justify-center size-14 rounded-full bg-[var(--color-error-subtle)]">
              <.icon name="hero-exclamation-triangle" class="size-7 text-[var(--color-error)]" />
            </div>
          </div>
          <h2 class="text-lg font-semibold text-[var(--color-text-primary)]">Invitation Invalid</h2>
          <p class="text-sm text-[var(--color-text-secondary)]">{@error}</p>
          <UI.button navigate={~p"/users/log-in"} size="sm">
            Go to Login
          </UI.button>
        </div>
      <% else %>
        <div class="space-y-6">
          <div class="text-center">
            <h1 class="text-xl font-semibold text-[var(--color-text-primary)]">
              You've been invited!
            </h1>
            <p class="mt-1 text-sm text-[var(--color-text-secondary)]">
              Join as <strong class="text-[var(--color-text-primary)]">{@invitation.email}</strong>
            </p>
          </div>

          <UI.simple_form for={@form} id="invitation-form" phx-change="validate" phx-submit="accept">
            <UI.input field={@form[:password]} type="password" label="Create your password" required />
            <UI.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm password"
              required
            />

            <%= if Application.get_env(:kith, :require_tos_acceptance, false) do %>
              <div class="flex items-start gap-2">
                <UI.input
                  field={@form[:tos_accepted]}
                  type="checkbox"
                  label={
                    ~H'I accept the <.link navigate="/terms" class="text-[var(--color-accent)] hover:underline" target="_blank">Terms of Service</.link>'
                  }
                />
              </div>
            <% end %>

            <:actions>
              <UI.button phx-disable-with="Joining..." class="w-full">
                Accept invitation and join
              </UI.button>
            </:actions>
          </UI.simple_form>
        </div>
      <% end %>
    </Layouts.auth>
    """
  end
end
