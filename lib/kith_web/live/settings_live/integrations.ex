defmodule KithWeb.SettingsLive.Integrations do
  use KithWeb, :live_view

  alias Kith.Immich.Settings, as: ImmichSettings
  alias Kith.Contacts

  import KithWeb.SettingsLive.SettingsLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Integrations")
     |> assign(:account, nil)
     |> assign(:immich_url, "")
     |> assign(:immich_api_key_set, false)
     |> assign(:immich_enabled, false)
     |> assign(:immich_status, "disabled")
     |> assign(:immich_failures, 0)
     |> assign(:immich_last_synced, nil)
     |> assign(:immich_pending_count, 0)
     |> assign(:test_result, nil)
     |> assign(:saving, false)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    user = socket.assigns.current_scope.user

    unless Kith.Policy.can?(user, :manage, :account) do
      {:noreply,
       socket
       |> put_flash(:error, "You do not have permission to manage integrations.")
       |> push_navigate(to: ~p"/")}
    else
      account = socket.assigns.current_scope.account
      settings = ImmichSettings.get_settings(account)
      pending_count = Contacts.count_needs_review(account.id)

      {:noreply,
       socket
       |> assign(:account, account)
       |> assign(:immich_url, settings.base_url || "")
       |> assign(:immich_api_key_set, settings.api_key != nil && settings.api_key != "")
       |> assign(:immich_enabled, settings.enabled)
       |> assign(:immich_status, settings.status)
       |> assign(:immich_failures, settings.consecutive_failures)
       |> assign(:immich_last_synced, settings.last_synced_at)
       |> assign(:immich_pending_count, pending_count)}
    end
  end

  @impl true
  def handle_event("save-immich", params, socket) do
    account = socket.assigns.account

    attrs = %{
      immich_base_url: params["immich_url"],
      immich_enabled: params["immich_enabled"] == "true"
    }

    # Only update API key if a new one was provided
    attrs =
      case params["immich_api_key"] do
        "" -> attrs
        nil -> attrs
        key -> Map.put(attrs, :immich_api_key, key)
      end

    case ImmichSettings.update_settings(account, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:account, updated)
         |> assign(:immich_url, updated.immich_base_url || "")
         |> assign(
           :immich_api_key_set,
           updated.immich_api_key != nil && updated.immich_api_key != ""
         )
         |> assign(:immich_enabled, updated.immich_enabled)
         |> put_flash(:info, "Immich settings saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings")}
    end
  end

  def handle_event("test-connection", _params, socket) do
    account = socket.assigns.account

    case ImmichSettings.test_connection(account) do
      :ok ->
        {:noreply, assign(socket, :test_result, :ok)}

      {:error, reason} ->
        {:noreply, assign(socket, :test_result, {:error, reason})}
    end
  end

  def handle_event("sync-now", _params, socket) do
    account = socket.assigns.account

    case Kith.Immich.trigger_sync(account) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Sync triggered — results will appear shortly")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "A sync is already in progress")}
    end
  end

  def handle_event("reset-retry", _params, socket) do
    account = socket.assigns.account

    {:ok, updated} =
      account
      |> Kith.Accounts.Account.immich_sync_changeset(%{
        immich_status: "ok",
        immich_consecutive_failures: 0
      })
      |> Kith.Repo.update()

    Kith.Immich.trigger_sync(updated)

    {:noreply,
     socket
     |> assign(:account, updated)
     |> assign(:immich_status, "ok")
     |> assign(:immich_failures, 0)
     |> put_flash(:info, "Circuit breaker reset — sync triggered")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.settings_shell current_path={@current_path} current_scope={@current_scope}>
        <.header>
          Integrations
          <:subtitle>Manage external service connections</:subtitle>
        </.header>

        <%!-- Immich Section --%>
        <div class="mt-8 bg-base-100 border border-base-300 rounded-lg p-6">
          <h2 class="text-lg font-semibold mb-4">Immich Photo Integration</h2>

          <%!-- Circuit breaker error banner --%>
          <div
            :if={@immich_status == "error"}
            class="mb-4 bg-error/10 border border-error/30 rounded-lg p-4"
          >
            <p class="text-error font-medium">Connection Error</p>
            <p class="text-error/80 text-sm mt-1">
              Immich sync has failed {@immich_failures} consecutive times and has been paused.
            </p>
            <button
              phx-click="reset-retry"
              class="mt-2 text-sm btn btn-error btn-sm"
            >
              Reset &amp; Retry
            </button>
          </div>

          <form phx-submit="save-immich" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-base-content mb-1">Server URL</label>
              <input
                type="url"
                name="immich_url"
                value={@immich_url}
                placeholder="https://immich.example.com"
                class="input input-bordered w-full"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-base-content mb-1">API Key</label>
              <input
                type="password"
                name="immich_api_key"
                placeholder={if @immich_api_key_set, do: "••••••••••••••••", else: "Enter API key"}
                class="input input-bordered w-full"
              />
              <p :if={@immich_api_key_set} class="text-xs text-base-content/50 mt-1">
                Leave blank to keep existing key
              </p>
            </div>

            <div class="flex items-center gap-2">
              <input type="hidden" name="immich_enabled" value="false" />
              <input
                type="checkbox"
                name="immich_enabled"
                value="true"
                checked={@immich_enabled}
                class="checkbox checkbox-sm"
              />
              <label class="text-sm text-base-content">Enable Immich sync</label>
            </div>

            <div class="flex gap-3 pt-2">
              <button type="submit" class="btn btn-primary btn-sm">
                Save
              </button>
              <button
                type="button"
                phx-click="test-connection"
                class="btn btn-ghost btn-sm border border-base-300"
              >
                Test Connection
              </button>
              <button
                type="button"
                phx-click="sync-now"
                disabled={!@immich_api_key_set || !@immich_enabled}
                class="btn btn-ghost btn-sm border border-base-300 disabled:opacity-50"
              >
                Sync Now
              </button>
            </div>
          </form>

          <%!-- Test connection result --%>
          <div :if={@test_result == :ok} class="mt-3 text-success text-sm">
            Connected successfully
          </div>
          <div :if={match?({:error, _}, @test_result)} class="mt-3 text-error text-sm">
            Could not connect: {format_error(elem(@test_result, 1))}
          </div>

          <%!-- Sync status --%>
          <div
            :if={@immich_last_synced}
            class="mt-4 pt-4 border-t border-base-300 text-sm text-base-content/60"
          >
            <p>Last synced: {Calendar.strftime(@immich_last_synced, "%b %d, %Y at %H:%M UTC")}</p>
            <p :if={@immich_pending_count > 0} class="mt-1">
              <.link navigate={~p"/contacts"} class="text-primary hover:underline">
                {@immich_pending_count} contact(s) need review
              </.link>
            </p>
          </div>
        </div>
      </.settings_shell>
    </Layouts.app>
    """
  end

  defp format_error(:unauthorized), do: "invalid API key"
  defp format_error(:not_found), do: "server not found — check URL"
  defp format_error(:timeout), do: "connection timed out"
  defp format_error(:network_error), do: "network error"
  defp format_error(:missing_url), do: "server URL is required"
  defp format_error(:missing_api_key), do: "API key is required"
  defp format_error({:unexpected_status, code}), do: "unexpected HTTP #{code}"
  defp format_error(other), do: inspect(other)
end
