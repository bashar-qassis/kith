defmodule KithWeb.UserLive.Registration do
  use KithWeb, :live_view

  alias Kith.Accounts
  alias Kith.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
          action={~p"/users/log-in?_action=registered"}
          method="post"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <div
            x-data="{ pw: '' }"
            class="space-y-1"
          >
            <div class="fieldset mb-2">
              <label for={@form[:password].id}>
                <span class="label mb-1">Password</span>
                <input
                  type="password"
                  name={@form[:password].name}
                  id={@form[:password].id}
                  value={Phoenix.HTML.Form.normalize_value("password", @form[:password].value)}
                  class="w-full input"
                  autocomplete="new-password"
                  required
                  x-model="pw"
                />
              </label>
            </div>
            <div
              class="h-1.5 w-full rounded-full bg-base-200 overflow-hidden"
              x-show="pw.length > 0"
              x-cloak
            >
              <div
                class="h-full rounded-full transition-all duration-300"
                x-bind:class="pw.length < 8 ? 'bg-error w-1/4' : pw.length < 12 ? 'bg-warning w-1/2' : pw.length < 16 ? 'bg-info w-3/4' : 'bg-success w-full'"
              >
              </div>
            </div>

            <p
              class="text-xs"
              x-show="pw.length > 0"
              x-cloak
              x-bind:class="pw.length < 8 ? 'text-error' : pw.length < 12 ? 'text-warning' : pw.length < 16 ? 'text-info' : 'text-success'"
              x-text="pw.length < 8 ? 'Too short' : pw.length < 12 ? 'Fair' : pw.length < 16 ? 'Good' : 'Strong'"
            >
            </p>
          </div>

          <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: KithWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    if Application.get_env(:kith, :disable_signup, false) do
      {:ok,
       socket
       |> put_flash(:error, "Registration is currently disabled.")
       |> redirect(to: ~p"/users/log-in")}
    else
      changeset = Accounts.change_user_registration(%User{})

      {:ok, assign(socket, form: to_form(changeset, as: "user"), trigger_submit: false),
       temporary_assigns: [form: nil]}
    end
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Accounts.deliver_user_confirmation_instructions(
          user,
          &url(~p"/users/confirm/#{&1}")
        )

        # Keep original params in the form so phx-trigger-action can POST
        # the email+password to the session controller for auto-login.
        changeset = Accounts.change_user_registration(%User{}, user_params)

        {:noreply,
         socket
         |> assign(trigger_submit: true)
         |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
