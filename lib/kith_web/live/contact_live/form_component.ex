defmodule KithWeb.ContactLive.FormComponent do
  use KithWeb, :live_component

  alias Kith.Contacts
  alias Kith.Contacts.Contact

  @impl true
  def update(%{contact: contact, account_id: account_id} = assigns, socket) do
    changeset = Contact.update_changeset(contact, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:genders, Contacts.list_genders(account_id))
     |> assign(:show_deceased_at, contact.deceased || false)}
  end

  @impl true
  def handle_event("validate", %{"contact" => contact_params}, socket) do
    changeset =
      socket.assigns.contact
      |> Contact.update_changeset(contact_params)
      |> Map.put(:action, :validate)

    show_deceased = contact_params["deceased"] == "true"

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:show_deceased_at, show_deceased)}
  end

  def handle_event("save", %{"contact" => contact_params}, socket) do
    save_contact(socket, socket.assigns.action, contact_params)
  end

  defp save_contact(socket, :new, contact_params) do
    account_id = socket.assigns.account_id
    user = socket.assigns.current_scope.user

    case Contacts.create_contact(account_id, contact_params) do
      {:ok, contact} ->
        Kith.AuditLogs.log_event(account_id, user, "Contact created",
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

  defp save_contact(socket, :edit, contact_params) do
    account_id = socket.assigns.account_id
    user = socket.assigns.current_scope.user
    contact = socket.assigns.contact

    case Contacts.update_contact(contact, contact_params) do
      {:ok, updated_contact} ->
        Kith.AuditLogs.log_event(account_id, user, "Contact updated",
          contact_id: updated_contact.id,
          contact_name: updated_contact.display_name,
          metadata: %{changed_fields: changed_fields(contact_params, contact)}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Contact updated successfully.")
         |> push_navigate(to: ~p"/contacts/#{updated_contact.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp changed_fields(params, contact) do
    params
    |> Enum.filter(fn {key, value} ->
      current = Map.get(contact, String.to_existing_atom(key))
      to_string(current) != to_string(value)
    end)
    |> Enum.map(fn {key, _} -> key end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@changeset}
        id="contact-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="form-control">
            <label class="label"><span class="label-text">First Name *</span></label>
            <input
              type="text"
              name="contact[first_name]"
              value={Ecto.Changeset.get_field(@changeset, :first_name)}
              class="input input-bordered"
              required
            />
            <span
              :for={msg <- changeset_errors(@changeset, :first_name)}
              class="label-text-alt text-error"
            >
              {msg}
            </span>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Last Name</span></label>
            <input
              type="text"
              name="contact[last_name]"
              value={Ecto.Changeset.get_field(@changeset, :last_name)}
              class="input input-bordered"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Nickname</span></label>
            <input
              type="text"
              name="contact[nickname]"
              value={Ecto.Changeset.get_field(@changeset, :nickname)}
              class="input input-bordered"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Gender</span></label>
            <select name="contact[gender_id]" class="select select-bordered">
              <option value="">Select gender</option>
              <%= for gender <- @genders do %>
                <option
                  value={gender.id}
                  selected={Ecto.Changeset.get_field(@changeset, :gender_id) == gender.id}
                >
                  {gender.name}
                </option>
              <% end %>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Birthdate</span></label>
            <input
              type="date"
              name="contact[birthdate]"
              value={Ecto.Changeset.get_field(@changeset, :birthdate)}
              class="input input-bordered"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Occupation</span></label>
            <input
              type="text"
              name="contact[occupation]"
              value={Ecto.Changeset.get_field(@changeset, :occupation)}
              class="input input-bordered"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Company</span></label>
            <input
              type="text"
              name="contact[company]"
              value={Ecto.Changeset.get_field(@changeset, :company)}
              class="input input-bordered"
            />
          </div>

          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                name="contact[deceased]"
                value="true"
                checked={Ecto.Changeset.get_field(@changeset, :deceased)}
                class="checkbox"
              />
              <span class="label-text">Deceased</span>
            </label>
          </div>

          <%= if @show_deceased_at do %>
            <div class="form-control">
              <label class="label"><span class="label-text">Date of Death</span></label>
              <input
                type="date"
                name="contact[deceased_at]"
                value={Ecto.Changeset.get_field(@changeset, :deceased_at)}
                class="input input-bordered"
              />
            </div>
          <% end %>
        </div>

        <div class="form-control mt-4">
          <label class="label"><span class="label-text">Description</span></label>
          <textarea
            name="contact[description]"
            class="textarea textarea-bordered h-24"
          >{Ecto.Changeset.get_field(@changeset, :description)}</textarea>
        </div>

        <div class="mt-6 flex justify-end gap-3">
          <.link navigate={@return_to} class="btn btn-ghost">Cancel</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
            {if @action == :new, do: "Create Contact", else: "Save Changes"}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp changeset_errors(changeset, field) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Map.get(field, [])
  end
end
