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
      <div>
        <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Label</span></label>
        <select name="address[label]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150">
          <option value="">—</option>
          <%= for label <- @labels do %>
            <option value={label} selected={@address_label == label}>{label}</option>
          <% end %>
        </select>
      </div>
      <div class="mt-2">
        <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Street</span></label>
        <input type="text" name="address[line1]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150" value={@line1} />
      </div>
      <div class="mt-2">
        <input
          type="text"
          name="address[line2]"
          class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
          placeholder="Apt, suite, etc."
          value={@line2}
        />
      </div>
      <div class="grid grid-cols-2 gap-3 mt-2">
        <div>
          <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">City</span></label>
          <input type="text" name="address[city]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150" value={@city} />
        </div>
        <div>
          <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Province/State</span></label>
          <input
            type="text"
            name="address[province]"
            class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
            value={@province}
          />
        </div>
      </div>
      <div class="grid grid-cols-2 gap-3 mt-2">
        <div>
          <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Postal Code</span></label>
          <input
            type="text"
            name="address[postal_code]"
            class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
            value={@postal_code}
          />
        </div>
        <div>
          <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Country</span></label>
          <input
            type="text"
            name="address[country]"
            class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
            value={@country}
          />
        </div>
      </div>
      <div class="flex gap-2 mt-3">
        <button type="submit" class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer">Save</button>
        <button
          type="button"
          phx-click="cancel-form"
          phx-target={@target}
          class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-sunken)] hover:text-[var(--color-text-primary)] transition-colors cursor-pointer"
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
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-[var(--color-text-primary)]">Addresses</h3>
        <%= if @can_edit do %>
          <button id={"add-address-#{@contact_id}"} phx-click="show-form" phx-target={@myself} class="rounded-[var(--radius-md)] p-1 text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] hover:bg-[var(--color-surface-sunken)] transition-colors cursor-pointer">
            <.icon name="hero-plus" class="size-4" />
          </button>
        <% end %>
      </div>

      <%= if @show_form do %>
        <div class="mb-4">
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
      <% end %>

      <%= if @addresses == [] and not @show_form do %>
        <KithUI.empty_state
          size={:compact}
          icon="hero-map-pin"
          title="No addresses"
          message="Add a home, work, or other address for this person."
        >
          <:actions :if={@can_edit}>
            <button phx-click="show-form" phx-target={@myself} class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer">
              Add Address
            </button>
          </:actions>
        </KithUI.empty_state>
      <% end %>

      <div class="space-y-3">
        <%= for addr <- @addresses do %>
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
              <div class="flex items-start gap-2 min-w-0">
                <.icon name="hero-map-pin" class="size-4 text-[var(--color-accent)] mt-0.5 shrink-0" />
                <div class="min-w-0">
                  <%= if addr.label do %>
                    <span class="inline-flex items-center rounded-[var(--radius-full)] px-2 py-0.5 text-xs font-medium bg-[var(--color-surface-sunken)] text-[var(--color-text-secondary)] border border-[var(--color-border)] mb-1">{addr.label}</span>
                  <% end %>
                  <p class="text-sm text-[var(--color-text-primary)] break-words">{format_address(addr)}</p>
                  <a
                    href={maps_url(addr)}
                    target="_blank"
                    class="text-[var(--color-accent)] hover:text-[var(--color-accent-hover)] transition-colors text-xs mt-0.5 inline-block"
                  >
                    Open in Maps
                  </a>
                </div>
              </div>
              <%= if @can_edit do %>
                <div class="flex gap-2 text-xs shrink-0 ms-2">
                  <button
                    phx-click="edit"
                    phx-value-id={addr.id}
                    phx-target={@myself}
                    class="text-[var(--color-accent)] hover:text-[var(--color-accent-hover)] transition-colors cursor-pointer"
                  >
                    Edit
                  </button>
                  <button
                    phx-click="delete"
                    phx-value-id={addr.id}
                    phx-target={@myself}
                    data-confirm="Delete this address?"
                    class="text-[var(--color-error)] hover:text-[var(--color-error)] transition-colors cursor-pointer"
                  >
                    Delete
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
