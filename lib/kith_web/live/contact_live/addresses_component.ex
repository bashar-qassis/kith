defmodule KithWeb.ContactLive.AddressesComponent do
  use KithWeb, :live_component

  alias Kith.Contacts

  @labels ~w(Home Work Other)

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:addresses, [])
     |> assign(:show_form, false)
     |> assign(:editing_id, nil)}
  end

  @impl true
  def update(assigns, socket) do
    addresses = Contacts.list_addresses(assigns.contact_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:addresses, addresses)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, true) |> assign(:editing_id, nil)}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_id, nil)}
  end

  def handle_event("save", %{"address" => params}, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    case Contacts.create_address(contact, params) do
      {:ok, _} ->
        addresses = Contacts.list_addresses(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:addresses, addresses)
         |> assign(:show_form, false)
         |> put_flash(:info, "Address added.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save address.")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:editing_id, String.to_integer(id)) |> assign(:show_form, false)}
  end

  def handle_event("update", %{"address" => params}, socket) do
    address = Contacts.get_address!(socket.assigns.account_id, socket.assigns.editing_id)

    case Contacts.update_address(address, params) do
      {:ok, _} ->
        addresses = Contacts.list_addresses(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:addresses, addresses)
         |> assign(:editing_id, nil)
         |> put_flash(:info, "Address updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update address.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    address = Contacts.get_address!(socket.assigns.account_id, String.to_integer(id))
    {:ok, _} = Contacts.delete_address(address)
    addresses = Contacts.list_addresses(socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:addresses, addresses)
     |> put_flash(:info, "Address deleted.")}
  end

  defp format_address(address) do
    [
      address.line1,
      address.line2,
      address.city,
      address.province,
      address.postal_code,
      address.country
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
  end

  defp maps_url(address) do
    query =
      [address.line1, address.city, address.province, address.postal_code, address.country]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(", ")
      |> URI.encode()

    "https://www.google.com/maps/search/?api=1&query=#{query}"
  end

  defp address_form(assigns) do
    ~H"""
    <.form for={%{}} phx-submit={@action} phx-target={@target}>
      <div class="form-control">
        <label class="label"><span class="label-text">Label</span></label>
        <select name="address[label]" class="select select-bordered select-sm">
          <option value="">—</option>
          <%= for label <- @labels do %>
            <option value={label} selected={@address_label == label}>{label}</option>
          <% end %>
        </select>
      </div>
      <div class="form-control mt-2">
        <label class="label"><span class="label-text">Street</span></label>
        <input type="text" name="address[line1]" class="input input-bordered input-sm" value={@line1} />
      </div>
      <div class="form-control mt-2">
        <input
          type="text"
          name="address[line2]"
          class="input input-bordered input-sm"
          placeholder="Apt, suite, etc."
          value={@line2}
        />
      </div>
      <div class="grid grid-cols-2 gap-3 mt-2">
        <div class="form-control">
          <label class="label"><span class="label-text">City</span></label>
          <input type="text" name="address[city]" class="input input-bordered input-sm" value={@city} />
        </div>
        <div class="form-control">
          <label class="label"><span class="label-text">Province/State</span></label>
          <input
            type="text"
            name="address[province]"
            class="input input-bordered input-sm"
            value={@province}
          />
        </div>
      </div>
      <div class="grid grid-cols-2 gap-3 mt-2">
        <div class="form-control">
          <label class="label"><span class="label-text">Postal Code</span></label>
          <input
            type="text"
            name="address[postal_code]"
            class="input input-bordered input-sm"
            value={@postal_code}
          />
        </div>
        <div class="form-control">
          <label class="label"><span class="label-text">Country</span></label>
          <input
            type="text"
            name="address[country]"
            class="input input-bordered input-sm"
            value={@country}
          />
        </div>
      </div>
      <div class="flex gap-2 mt-3">
        <button type="submit" class="btn btn-sm btn-primary">Save</button>
        <button
          type="button"
          phx-click="cancel-form"
          phx-target={@target}
          class="btn btn-sm btn-ghost"
        >
          Cancel
        </button>
      </div>
    </.form>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :labels, @labels)

    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Addresses</h2>
        <%= if @can_edit do %>
          <button phx-click="show-form" phx-target={@myself} class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Address
          </button>
        <% end %>
      </div>

      <%= if @show_form do %>
        <div class="card bg-base-100 shadow-sm mb-4">
          <div class="card-body p-4">
            <.address_form
              action="save"
              target={@myself}
              labels={@labels}
              address_label=""
              line1=""
              line2=""
              city=""
              province=""
              postal_code=""
              country=""
            />
          </div>
        </div>
      <% end %>

      <%= if @addresses == [] do %>
        <p class="text-base-content/60">No addresses yet.</p>
      <% end %>

      <div class="space-y-3">
        <%= for addr <- @addresses do %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <%= if @editing_id == addr.id do %>
                <.address_form
                  action="update"
                  target={@myself}
                  labels={@labels}
                  address_label={addr.label || ""}
                  line1={addr.line1 || ""}
                  line2={addr.line2 || ""}
                  city={addr.city || ""}
                  province={addr.province || ""}
                  postal_code={addr.postal_code || ""}
                  country={addr.country || ""}
                />
              <% else %>
                <div class="flex items-start justify-between">
                  <div class="flex items-start gap-3">
                    <.icon name="hero-map-pin" class="size-5 text-primary mt-0.5" />
                    <div>
                      <%= if addr.label do %>
                        <span class="badge badge-sm badge-outline mb-1">{addr.label}</span>
                      <% end %>
                      <p class="text-sm">{format_address(addr)}</p>
                      <a
                        href={maps_url(addr)}
                        target="_blank"
                        class="link link-primary text-xs mt-1 inline-block"
                      >
                        Open in Maps
                      </a>
                    </div>
                  </div>
                  <%= if @can_edit do %>
                    <div class="flex gap-2 text-xs shrink-0">
                      <button
                        phx-click="edit"
                        phx-value-id={addr.id}
                        phx-target={@myself}
                        class="link link-hover"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="delete"
                        phx-value-id={addr.id}
                        phx-target={@myself}
                        data-confirm="Delete this address?"
                        class="link link-hover text-error"
                      >
                        Delete
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
