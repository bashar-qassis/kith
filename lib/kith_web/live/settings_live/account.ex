defmodule KithWeb.SettingsLive.Account do
  @moduledoc """
  Account Settings page — account name, timezone, send_hour,
  feature module toggles, notification windows, and account deletion.
  Admin-only.
  """

  use KithWeb, :live_view

  alias Kith.Accounts
  alias Kith.Reminders

  import KithWeb.SettingsLive.SettingsLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Account Settings")
     |> assign(:account, nil)
     |> assign(:rules, [])
     |> assign(:account_form, nil)
     |> assign(:delete_confirmation, "")
     |> assign(:feature_flags, %{})}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    user = socket.assigns.current_scope.user

    unless Kith.Policy.can?(user, :manage, :account) do
      {:noreply,
       socket
       |> put_flash(:error, "You do not have permission to access account settings.")
       |> push_navigate(to: ~p"/")}
    else
      account = socket.assigns.current_scope.account
      rules = Reminders.list_reminder_rules(account.id)

      {:noreply,
       socket
       |> assign(:account, account)
       |> assign(:rules, rules)
       |> assign(:feature_flags, account.feature_flags || %{})
       |> assign(:account_form, to_form(Accounts.Account.settings_changeset(account, %{})))}
    end
  end

  @impl true
  def handle_event("save-account", %{"account" => params}, socket) do
    case Accounts.update_account(socket.assigns.account, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:account, updated)
         |> assign(:account_form, to_form(Accounts.Account.settings_changeset(updated, %{})))
         |> put_flash(:info, "Account settings updated")}

      {:error, changeset} ->
        {:noreply, assign(socket, :account_form, to_form(changeset))}
    end
  end

  def handle_event("toggle-feature", %{"feature" => feature}, socket) do
    account = socket.assigns.account
    flags = socket.assigns.feature_flags
    new_flags = Map.update(flags, feature, true, &(!&1))

    case Accounts.update_account(account, %{feature_flags: new_flags}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:account, updated)
         |> assign(:feature_flags, updated.feature_flags || %{})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update feature toggle")}
    end
  end

  def handle_event("toggle-rule", %{"id" => id}, socket) do
    rule = Reminders.get_reminder_rule!(socket.assigns.account.id, String.to_integer(id))

    case Reminders.update_reminder_rule(rule, %{active: !rule.active}) do
      {:ok, _rule} ->
        rules = Reminders.list_reminder_rules(socket.assigns.account.id)
        {:noreply, assign(socket, :rules, rules)}

      {:error, :cannot_deactivate_on_day_rule} ->
        {:noreply, put_flash(socket, :error, "The 'On the day' reminder cannot be turned off")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update rule")}
    end
  end

  def handle_event("validate-delete", %{"confirmation" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  def handle_event("delete-account", _params, socket) do
    account = socket.assigns.account

    if socket.assigns.delete_confirmation == account.name do
      case {:error, :not_implemented} do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Account deleted.")
           |> redirect(to: ~p"/")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete account.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Account name does not match.")}
    end
  end

  @feature_modules [
    {"reminders", "Reminders", "Enable birthday and event reminders"},
    {"activities", "Activities", "Track activities with contacts"},
    {"calls", "Phone Calls", "Log phone calls with contacts"},
    {"documents", "Documents", "Attach documents to contacts"},
    {"photos", "Photos", "Manage contact photos"},
    {"life_events", "Life Events", "Track important life events"}
  ]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :feature_modules, @feature_modules)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.settings_shell current_path={@current_path} current_scope={@current_scope}>
        <.header>
          Account Settings
          <:subtitle>Manage your account configuration</:subtitle>
        </.header>

        <%= if @account_form do %>
          <%!-- General settings --%>
          <div class="mt-8 bg-base-100 border border-base-300 rounded-lg p-6">
            <h2 class="text-lg font-semibold mb-4">General</h2>

            <.simple_form for={@account_form} phx-submit="save-account">
              <.input field={@account_form[:name]} type="text" label="Account Name" required />
              <.input
                field={@account_form[:timezone]}
                type="text"
                label="Timezone"
                placeholder="America/New_York"
              />
              <.input
                field={@account_form[:send_hour]}
                type="select"
                label="Reminder Send Hour"
                options={Enum.map(0..23, fn h -> {"#{String.pad_leading("#{h}", 2, "0")}:00", h} end)}
              />
              <p class="text-xs text-base-content/50 -mt-2">
                Changing timezone affects when reminders are sent. Changes take effect starting the following day.
              </p>
              <:actions>
                <.button>Save</.button>
              </:actions>
            </.simple_form>
          </div>

          <%!-- Feature module toggles --%>
          <div class="mt-6 bg-base-100 border border-base-300 rounded-lg p-6">
            <h2 class="text-lg font-semibold mb-1">Feature Modules</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Enable or disable feature modules for your account.
            </p>

            <div class="divide-y divide-base-200">
              <div
                :for={{key, label, description} <- @feature_modules}
                class="flex items-center justify-between py-3"
              >
                <div>
                  <span class="text-sm font-medium text-base-content">{label}</span>
                  <p class="text-xs text-base-content/50">{description}</p>
                </div>
                <button
                  phx-click="toggle-feature"
                  phx-value-feature={key}
                  class={[
                    "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none",
                    if(Map.get(@feature_flags, key, true), do: "bg-primary", else: "bg-base-300")
                  ]}
                >
                  <span class={[
                    "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                    if(Map.get(@feature_flags, key, true), do: "translate-x-5", else: "translate-x-0")
                  ]} />
                </button>
              </div>
            </div>
          </div>

          <%!-- Notification Windows --%>
          <div class="mt-6 bg-base-100 border border-base-300 rounded-lg p-6">
            <h2 class="text-lg font-semibold mb-1">Notification Windows</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Control how far in advance reminders send pre-notifications.
              Changes affect newly scheduled reminders only.
            </p>

            <div class="divide-y divide-base-200">
              <div :for={rule <- @rules} class="flex items-center justify-between py-3">
                <span class="text-sm text-base-content">
                  {format_rule_label(rule.days_before)}
                </span>

                <button
                  phx-click="toggle-rule"
                  phx-value-id={rule.id}
                  disabled={rule.days_before == 0}
                  title={
                    if rule.days_before == 0,
                      do: "The 'On the day' reminder cannot be turned off",
                      else: ""
                  }
                  class={[
                    "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none",
                    if(rule.active, do: "bg-primary", else: "bg-base-300"),
                    if(rule.days_before == 0, do: "opacity-50 cursor-not-allowed", else: "")
                  ]}
                >
                  <span class={[
                    "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                    if(rule.active, do: "translate-x-5", else: "translate-x-0")
                  ]} />
                </button>
              </div>
            </div>
          </div>

          <%!-- Account Deletion --%>
          <div class="mt-6 bg-base-100 border border-error/30 rounded-lg p-6">
            <h2 class="text-lg font-semibold text-error mb-1">Delete Account</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Permanently delete this account and all associated data. This action cannot be undone.
            </p>

            <form phx-submit="delete-account" phx-change="validate-delete">
              <label class="block text-sm font-medium text-base-content mb-2">
                Type <span class="font-bold">{@account.name}</span> to confirm
              </label>
              <input
                type="text"
                name="confirmation"
                value={@delete_confirmation}
                placeholder={@account.name}
                autocomplete="off"
                class="input input-bordered input-sm w-full max-w-xs"
              />
              <div class="mt-4">
                <button
                  type="submit"
                  disabled={@delete_confirmation != @account.name}
                  class="btn btn-error btn-sm disabled:opacity-50"
                >
                  Delete Account Permanently
                </button>
              </div>
            </form>
          </div>
        <% end %>
      </.settings_shell>
    </Layouts.app>
    """
  end

  defp format_rule_label(0), do: "On the day"
  defp format_rule_label(1), do: "1 day before"
  defp format_rule_label(days), do: "#{days} days before"
end
