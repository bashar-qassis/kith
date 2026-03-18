defmodule KithWeb.ContactLive.Edit do
  use KithWeb, :live_view

  alias Kith.Contacts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    account_id = socket.assigns.current_scope.account.id
    user = socket.assigns.current_scope.user
    Kith.Policy.authorize!(user, :update, :contact)

    contact =
      Contacts.get_contact!(account_id, String.to_integer(id))
      |> Kith.Repo.preload([:gender])

    {:ok,
     socket
     |> assign(:page_title, "Edit #{contact.display_name}")
     |> assign(:contact, contact)
     |> assign(:account_id, account_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 class="text-2xl font-bold mb-6">Edit {@contact.display_name}</h1>

      <.live_component
        module={KithWeb.ContactLive.FormComponent}
        id="contact-form"
        contact={@contact}
        action={:edit}
        account_id={@account_id}
        current_scope={@current_scope}
        return_to={~p"/contacts/#{@contact.id}"}
      />
    </div>
    """
  end
end
