defmodule KithWeb.ContactLive.New do
  use KithWeb, :live_view

  alias Kith.Contacts.Contact

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    Kith.Policy.authorize!(user, :create, :contact)

    {:ok,
     socket
     |> assign(:page_title, "New Contact")
     |> assign(:contact, %Contact{})
     |> assign(:account_id, socket.assigns.current_scope.account.id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 class="text-2xl font-bold mb-6">New Contact</h1>

      <.live_component
        module={KithWeb.ContactLive.FormComponent}
        id="contact-form"
        contact={@contact}
        action={:new}
        account_id={@account_id}
        current_scope={@current_scope}
        return_to={~p"/contacts"}
      />
    </div>
    """
  end
end
