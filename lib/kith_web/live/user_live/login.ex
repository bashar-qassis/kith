defmodule KithWeb.UserLive.Login do
  use KithWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                <%= unless Application.get_env(:kith, :disable_signup, false) do %>
                  Don't have an account? <.link
                    navigate={~p"/users/register"}
                    class="font-semibold text-brand hover:underline"
                    phx-no-format
                  >Sign up</.link> for an account now.
                <% end %>
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form"
          action={~p"/users/log-in"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={f[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
            required
          />

          <div class="flex items-center justify-between mt-2">
            <label class="flex items-center gap-2 text-sm">
              <input type="checkbox" name={f[:remember_me].name} value="true" class="checkbox" />
              Remember me
            </label>
            <.link navigate={~p"/users/reset-password"} class="text-sm text-brand hover:underline">
              Forgot password?
            </.link>
          </div>

          <.button class="btn btn-primary w-full mt-4">
            Log in <span aria-hidden="true">&rarr;</span>
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
