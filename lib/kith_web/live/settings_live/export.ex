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
        <UI.header>
          Export Contacts
          <:subtitle>Download your contact data</:subtitle>
        </UI.header>

        <div class="mt-6 space-y-6">
          <UI.card>
            <:header>vCard Export (.vcf)</:header>
            <p class="text-sm text-[var(--color-text-secondary)] mb-4">
              Download all {@contact_count} contacts as a vCard file.
              Compatible with Google Contacts, Apple Contacts, and Outlook.
            </p>
            <a
              href="/api/contacts/export.vcf"
              class="inline-flex items-center gap-2 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-4 py-2 text-sm font-medium hover:bg-[var(--color-accent-hover)] transition-colors"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download vCard (.vcf)
            </a>
          </UI.card>

          <UI.card>
            <:header>Full Data Export (JSON)</:header>
            <p class="text-sm text-[var(--color-text-secondary)] mb-4">
              Download all contacts with all associated data (notes, activities, calls,
              addresses, contact fields, tags, and more) as a JSON file.
            </p>
            <p :if={@contact_count >= 500} class="text-sm text-[var(--color-warning)] mb-4">
              Your account has {@contact_count} contacts. The export will be processed
              in the background and you'll receive an email when it's ready.
            </p>
            <a
              href="/api/export"
              class="inline-flex items-center gap-2 rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] text-[var(--color-text-primary)] px-4 py-2 text-sm font-medium hover:bg-[var(--color-surface-sunken)] transition-colors"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download JSON export
            </a>
          </UI.card>
        </div>
      </.settings_shell>
    </Layouts.app>
    """
  end
end
