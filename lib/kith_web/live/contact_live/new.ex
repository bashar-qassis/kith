defmodule KithWeb.ContactLive.New do
  use KithWeb, :live_view

  alias Kith.Contacts
  alias Kith.Contacts.Contact

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Contact")
     |> assign(:changeset, Contact.update_changeset(%Contact{}, %{}))
     |> assign(:genders, [])
     |> assign(:show_deceased_at, false)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    user = socket.assigns.current_scope.user

    unless Kith.Policy.can?(user, :create, :contact) do
      {:noreply,
       socket
       |> put_flash(:error, "You don't have permission to create contacts")
       |> push_navigate(to: ~p"/contacts")}
    else
      account_id = socket.assigns.current_scope.account.id

      {:noreply,
       socket
       |> assign(:account_id, account_id)
       |> assign(:genders, Contacts.list_genders(account_id))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <h1 class="text-2xl font-bold mb-6">New Contact</h1>

        <.simple_form
          for={@changeset}
          id="contact-form"
          as={:contact}
          phx-change="validate"
          phx-submit="save"
          :let={f}
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input
              field={f[:first_name]}
              type="text"
              label="First Name *"
              required
            />
            <.input field={f[:last_name]} type="text" label="Last Name" />
            <.input field={f[:nickname]} type="text" label="Nickname" />
            <.input
              field={f[:gender_id]}
              type="select"
              label="Gender"
              prompt="Select gender"
              options={Enum.map(@genders, &{&1.name, &1.id})}
            />
            <.input field={f[:birthdate]} type="date" label="Birthdate" />
            <.input field={f[:occupation]} type="text" label="Occupation" />
            <.input field={f[:company]} type="text" label="Company" />
            <.input field={f[:deceased]} type="checkbox" label="Deceased" />
            <.input field={f[:favorite]} type="checkbox" label="Favorite" />
          </div>

          <%= if @show_deceased_at do %>
            <.input field={f[:deceased_at]} type="date" label="Date of Death" />
          <% end %>

          <:actions>
            <.link navigate={~p"/contacts"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
              Create Contact
            </button>
          </:actions>
        </.simple_form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"contact" => contact_params}, socket) do
    changeset =
      %Contact{}
      |> Contact.update_changeset(contact_params)
      |> Map.put(:action, :validate)

    show_deceased = contact_params["deceased"] == "true"

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:show_deceased_at, show_deceased)}
  end

  def handle_event("save", %{"contact" => contact_params}, socket) do
    account_id = socket.assigns.account_id
    user = socket.assigns.current_scope.user

    case Contacts.create_contact(account_id, contact_params) do
      {:ok, contact} ->
        Kith.AuditLogs.log_event(account_id, user, :contact_created,
          contact_id: contact.id,
          contact_name: contact.display_name
        )

        {:noreply,
         socket
         |> put_flash(:info, "Contact created successfully.")
         |> push_navigate(to: ~p"/contacts/#{contact.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end
end
