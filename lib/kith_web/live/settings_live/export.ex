defmodule KithWeb.SettingsLive.Export do
  use KithWeb, :live_view

  alias Kith.Contacts

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    contact_count = Contacts.count_contacts(scope.account.id)

    {:ok,
     socket
     |> assign(:page_title, "Export Contacts")
     |> assign(:contact_count, contact_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <.header>
        Export Contacts
        <:subtitle>Download your contact data</:subtitle>
      </.header>

      <div class="mt-6 space-y-6">
        <%!-- vCard Export --%>
        <div class="bg-white border rounded-lg p-6">
          <h3 class="text-lg font-semibold mb-2">vCard Export (.vcf)</h3>
          <p class="text-sm text-gray-600 mb-4">
            Download all {@contact_count} contacts as a vCard file.
            Compatible with Google Contacts, Apple Contacts, and Outlook.
          </p>
          <a
            href="/api/contacts/export.vcf"
            class="inline-block bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 text-sm"
          >
            Download all contacts as vCard (.vcf)
          </a>
        </div>

        <%!-- JSON Export --%>
        <div class="bg-white border rounded-lg p-6">
          <h3 class="text-lg font-semibold mb-2">Full Data Export (JSON)</h3>
          <p class="text-sm text-gray-600 mb-4">
            Download all contacts with all associated data (notes, activities, calls,
            addresses, contact fields, tags, and more) as a JSON file.
          </p>
          <p :if={@contact_count >= 500} class="text-sm text-amber-600 mb-4">
            Your account has {@contact_count} contacts. The export will be processed
            in the background and you'll receive an email when it's ready.
          </p>
          <a
            href="/api/export"
            class="inline-block bg-gray-100 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-200 text-sm"
          >
            Download full data export (JSON)
          </a>
        </div>
      </div>
    </div>
    """
  end
end
