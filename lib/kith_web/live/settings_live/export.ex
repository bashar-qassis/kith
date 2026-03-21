defmodule KithWeb.SettingsLive.Export do
  use KithWeb, :live_view

  alias Kith.Contacts

  import KithWeb.SettingsLive.SettingsLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Export Contacts")
     |> assign(:contact_count, 0)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    account_id = socket.assigns.current_scope.account.id
    contact_count = Contacts.count_contacts(account_id)

    {:noreply, assign(socket, :contact_count, contact_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.settings_shell current_path={@current_path} current_scope={@current_scope}>
        <.header>
          Export Contacts
          <:subtitle>Download your contact data</:subtitle>
        </.header>

        <div class="mt-6 space-y-6">
          <%!-- vCard Export --%>
          <div class="bg-base-100 border border-base-300 rounded-lg p-6">
            <h3 class="text-lg font-semibold mb-2">vCard Export (.vcf)</h3>
            <p class="text-sm text-base-content/60 mb-4">
              Download all {@contact_count} contacts as a vCard file.
              Compatible with Google Contacts, Apple Contacts, and Outlook.
            </p>
            <a
              href="/api/contacts/export.vcf"
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download vCard (.vcf)
            </a>
          </div>

          <%!-- JSON Export --%>
          <div class="bg-base-100 border border-base-300 rounded-lg p-6">
            <h3 class="text-lg font-semibold mb-2">Full Data Export (JSON)</h3>
            <p class="text-sm text-base-content/60 mb-4">
              Download all contacts with all associated data (notes, activities, calls,
              addresses, contact fields, tags, and more) as a JSON file.
            </p>
            <p :if={@contact_count >= 500} class="text-sm text-warning mb-4">
              Your account has {@contact_count} contacts. The export will be processed
              in the background and you'll receive an email when it's ready.
            </p>
            <a
              href="/api/export"
              class="btn btn-ghost btn-sm border border-base-300"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download JSON export
            </a>
          </div>
        </div>
      </.settings_shell>
    </Layouts.app>
    """
  end
end
