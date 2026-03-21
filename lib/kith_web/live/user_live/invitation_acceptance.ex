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
      nil ->
        {:noreply,
         socket
         |> assign(:error, "This invitation has expired or has already been used.")
         |> assign(:token, token)}

      invitation ->
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
    <div class="min-h-screen flex items-center justify-center bg-base-200 px-4">
      <div class="w-full max-w-md">
        <div class="text-center mb-6">
          <h1 class="text-2xl font-bold">Kith</h1>
        </div>

        <.card>
          <%= if @error do %>
            <div class="text-center space-y-4">
              <.icon name="hero-exclamation-triangle" class="size-12 text-error mx-auto" />
              <h2 class="text-lg font-semibold">Invitation Invalid</h2>
              <p class="text-base-content/70">{@error}</p>
              <.link navigate={~p"/users/log-in"} class="btn btn-primary btn-sm">
                Go to Login
              </.link>
            </div>
          <% else %>
            <div class="text-center mb-6">
              <h2 class="text-lg font-semibold">You've been invited!</h2>
              <p class="text-sm text-base-content/70 mt-1">
                Join as <strong>{@invitation.email}</strong>
              </p>
            </div>

            <.simple_form for={@form} id="invitation-form" phx-change="validate" phx-submit="accept">
              <.input field={@form[:password]} type="password" label="Create your password" required />
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm password"
                required
              />

              <:actions>
                <.button phx-disable-with="Joining..." class="w-full">
                  Accept invitation and join
                </.button>
              </:actions>
            </.simple_form>
          <% end %>
        </.card>
      </div>
    </div>
    """
  end
end
