defmodule KithWeb.SettingsLive.Account do
  @moduledoc """
  Account Settings page — account name, timezone, send_hour,
  and Notification Windows (reminder rules) sub-section.
  """

  use KithWeb, :live_view

  alias Kith.Accounts
  alias Kith.Reminders

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    account = scope.account
    user = scope.user
    rules = Reminders.list_reminder_rules(account.id)

    {:ok,
     socket
     |> assign(:page_title, "Account Settings")
     |> assign(:account, account)
     |> assign(:role, user.role)
     |> assign(:rules, rules)
     |> assign(:account_form, to_form(Accounts.Account.settings_changeset(account, %{})))}
  end

  @impl true
  def handle_event("save-account", %{"account" => params}, socket) do
    if socket.assigns.role != "admin" do
      {:noreply, put_flash(socket, :error, "Only admins can update account settings")}
    else
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
  end

  def handle_event("toggle-rule", %{"id" => id}, socket) do
    if socket.assigns.role != "admin" do
      {:noreply, put_flash(socket, :error, "Only admins can change reminder rules")}
    else
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
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <.header>
        Account Settings
        <:subtitle>Manage your account configuration</:subtitle>
      </.header>

      <%!-- Account info (admin only) --%>
      <div :if={@role == "admin"} class="mt-8 bg-white border rounded-lg p-6">
        <h2 class="text-lg font-semibold mb-4">General</h2>

        <.simple_form for={@account_form} phx-submit="save-account">
          <.input field={@account_form[:name]} type="text" label="Account Name" required />
          <.input
            field={@account_form[:timezone]}
            type="text"
            label="Timezone"
            placeholder="America/New_York"
          />
          <.input field={@account_form[:locale]} type="text" label="Locale" placeholder="en" />
          <.input
            field={@account_form[:send_hour]}
            type="number"
            label="Reminder Send Hour (0-23)"
            min="0"
            max="23"
          />
          <p class="text-xs text-gray-500 -mt-2">
            Changing timezone affects when reminders are sent. Changes take effect starting the following day.
          </p>
          <:actions>
            <.button>Save</.button>
          </:actions>
        </.simple_form>
      </div>

      <%!-- Notification Windows — visible to admin (toggleable) and editor (read-only) --%>
      <div :if={@role in ["admin", "editor"]} class="mt-8 bg-white border rounded-lg p-6">
        <h2 class="text-lg font-semibold mb-1">Notification Windows</h2>
        <p class="text-sm text-gray-500 mb-4">
          Control how far in advance reminders send pre-notifications.
          Changes affect newly scheduled reminders only.
        </p>

        <div class="divide-y">
          <div :for={rule <- @rules} class="flex items-center justify-between py-3">
            <span class="text-sm text-gray-800">
              {format_rule_label(rule.days_before)}
            </span>

            <%= if @role == "admin" do %>
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
                  if(rule.active, do: "bg-blue-600", else: "bg-gray-200"),
                  if(rule.days_before == 0, do: "opacity-50 cursor-not-allowed", else: "")
                ]}
              >
                <span class={[
                  "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                  if(rule.active, do: "translate-x-5", else: "translate-x-0")
                ]} />
              </button>
            <% else %>
              <span class={[
                "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
                if(rule.active, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800")
              ]}>
                {if rule.active, do: "Active", else: "Inactive"}
              </span>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_rule_label(0), do: "On the day"
  defp format_rule_label(1), do: "1 day before"
  defp format_rule_label(days), do: "#{days} days before"
end
