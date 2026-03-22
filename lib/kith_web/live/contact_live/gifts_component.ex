defmodule KithWeb.ContactLive.GiftsComponent do
  use KithWeb, :live_component

  alias Kith.Gifts
  alias Kith.Contacts.Gift

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:gifts, [])
     |> assign(:show_form, false)
     |> assign(:editing_gift_id, nil)}
  end

  @impl true
  def update(assigns, socket) do
    gifts = Gifts.list_gifts(assigns.account_id, assigns.contact_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:gifts, gifts)
     |> assign_new(:changeset, fn -> Gift.changeset(%Gift{}, %{}) end)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_gift_id, nil)
     |> assign(:changeset, Gift.changeset(%Gift{}, %{}))}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_gift_id, nil)}
  end

  def handle_event("save-gift", %{"gift" => gift_params}, socket) do
    params = Map.put(gift_params, "contact_id", socket.assigns.contact_id)

    case Gifts.create_gift(socket.assigns.account_id, socket.assigns.current_user_id, params) do
      {:ok, _gift} ->
        gifts = Gifts.list_gifts(socket.assigns.account_id, socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:gifts, gifts)
         |> assign(:show_form, false)
         |> put_flash(:info, "Gift added.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("edit-gift", %{"id" => id}, socket) do
    gift = Gifts.get_gift!(socket.assigns.account_id, String.to_integer(id))
    changeset = Gift.changeset(gift, %{})

    {:noreply,
     socket
     |> assign(:editing_gift_id, gift.id)
     |> assign(:show_form, false)
     |> assign(:changeset, changeset)}
  end

  def handle_event("update-gift", %{"gift" => gift_params}, socket) do
    gift = Gifts.get_gift!(socket.assigns.account_id, socket.assigns.editing_gift_id)

    case Gifts.update_gift(gift, gift_params) do
      {:ok, _gift} ->
        gifts = Gifts.list_gifts(socket.assigns.account_id, socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:gifts, gifts)
         |> assign(:editing_gift_id, nil)
         |> put_flash(:info, "Gift updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("delete-gift", %{"id" => id}, socket) do
    gift = Gifts.get_gift!(socket.assigns.account_id, String.to_integer(id))
    {:ok, _} = Gifts.delete_gift(gift)
    gifts = Gifts.list_gifts(socket.assigns.account_id, socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:gifts, gifts)
     |> put_flash(:info, "Gift deleted.")}
  end

  defp direction_badge_class("given"),
    do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400"

  defp direction_badge_class("received"),
    do: "bg-violet-100 text-violet-700 dark:bg-violet-900/30 dark:text-violet-400"

  defp direction_badge_class(_),
    do: "bg-gray-100 text-gray-700 dark:bg-gray-900/30 dark:text-gray-400"

  defp status_badge_class("idea"),
    do: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"

  defp status_badge_class("purchased"),
    do: "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400"

  defp status_badge_class("given"),
    do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400"

  defp status_badge_class("received"),
    do: "bg-violet-100 text-violet-700 dark:bg-violet-900/30 dark:text-violet-400"

  defp status_badge_class(_),
    do: "bg-gray-100 text-gray-700 dark:bg-gray-900/30 dark:text-gray-400"

  defp occasion_label("birthday"), do: "Birthday"
  defp occasion_label("christmas"), do: "Christmas"
  defp occasion_label("anniversary"), do: "Anniversary"
  defp occasion_label("wedding"), do: "Wedding"
  defp occasion_label("thank_you"), do: "Thank You"
  defp occasion_label("other"), do: "Other"
  defp occasion_label(nil), do: nil
  defp occasion_label(val), do: String.capitalize(val)

  defp format_amount(nil), do: nil
  defp format_amount(%Decimal{} = amount), do: Decimal.to_string(amount, :normal)
  defp format_amount(amount), do: to_string(amount)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Gifts</h2>
        <%= if @can_edit do %>
          <button
            id={"add-gift-#{@contact_id}"}
            phx-click="show-form"
            phx-target={@myself}
            class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
          >
            <.icon name="hero-plus" class="size-4" /> Add Gift
          </button>
        <% end %>
      </div>

      <%!-- Add gift form --%>
      <%= if @show_form do %>
        <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-sm mb-4">
          <div class="p-4">
            <.form for={%{}} phx-submit="save-gift" phx-target={@myself}>
              <div class="space-y-3">
                <div class="grid grid-cols-2 gap-3">
                  <div>
                    <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                      Name *
                    </label>
                    <input
                      type="text"
                      name="gift[name]"
                      required
                      class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                      Direction *
                    </label>
                    <select
                      name="gift[direction]"
                      required
                      class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                    >
                      <option value="">Select...</option>
                      <option value="given">Given</option>
                      <option value="received">Received</option>
                    </select>
                  </div>
                </div>
                <div>
                  <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                    Description
                  </label>
                  <textarea
                    name="gift[description]"
                    rows="2"
                    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                  ></textarea>
                </div>
                <div class="grid grid-cols-2 gap-3">
                  <div>
                    <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                      Occasion
                    </label>
                    <select
                      name="gift[occasion]"
                      class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                    >
                      <option value="">None</option>
                      <option value="birthday">Birthday</option>
                      <option value="christmas">Christmas</option>
                      <option value="anniversary">Anniversary</option>
                      <option value="wedding">Wedding</option>
                      <option value="thank_you">Thank You</option>
                      <option value="other">Other</option>
                    </select>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                      Date
                    </label>
                    <input
                      type="date"
                      name="gift[date]"
                      class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                    />
                  </div>
                </div>
                <div class="grid grid-cols-2 gap-3">
                  <div>
                    <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                      Amount
                    </label>
                    <input
                      type="number"
                      name="gift[amount]"
                      step="0.01"
                      min="0"
                      class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                      Status
                    </label>
                    <select
                      name="gift[status]"
                      class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                    >
                      <option value="idea" selected>Idea</option>
                      <option value="purchased">Purchased</option>
                      <option value="given">Given</option>
                      <option value="received">Received</option>
                    </select>
                  </div>
                </div>
                <div>
                  <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                    Purchase URL
                  </label>
                  <input
                    type="url"
                    name="gift[purchase_url]"
                    placeholder="https://..."
                    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                  />
                </div>
              </div>
              <div class="flex gap-2 mt-3">
                <button
                  type="submit"
                  class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
                >
                  Save
                </button>
                <button
                  type="button"
                  phx-click="cancel-form"
                  phx-target={@myself}
                  class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-sunken)] hover:text-[var(--color-text-primary)] transition-colors cursor-pointer"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- Gifts list --%>
      <%= if @gifts == [] and not @show_form do %>
        <KithUI.empty_state
          size={:compact}
          icon="hero-gift"
          title="No gifts yet"
          message="Keep track of gifts given and received for this contact."
        >
          <:actions :if={@can_edit}>
            <button
              phx-click="show-form"
              phx-target={@myself}
              class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
            >
              Add Gift
            </button>
          </:actions>
        </KithUI.empty_state>
      <% end %>

      <div class="space-y-3">
        <%= for gift <- @gifts do %>
          <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-sm">
            <div class="p-4">
              <%= if @editing_gift_id == gift.id do %>
                <%!-- Inline edit form --%>
                <.form for={%{}} phx-submit="update-gift" phx-target={@myself}>
                  <div class="space-y-3">
                    <div class="grid grid-cols-2 gap-3">
                      <div>
                        <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                          Name *
                        </label>
                        <input
                          type="text"
                          name="gift[name]"
                          value={gift.name}
                          required
                          class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                          Direction *
                        </label>
                        <select
                          name="gift[direction]"
                          required
                          class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                        >
                          <option value="given" selected={gift.direction == "given"}>Given</option>
                          <option value="received" selected={gift.direction == "received"}>
                            Received
                          </option>
                        </select>
                      </div>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                        Description
                      </label>
                      <textarea
                        name="gift[description]"
                        rows="2"
                        class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                      >{gift.description}</textarea>
                    </div>
                    <div class="grid grid-cols-2 gap-3">
                      <div>
                        <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                          Occasion
                        </label>
                        <select
                          name="gift[occasion]"
                          class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                        >
                          <option value="">None</option>
                          <option value="birthday" selected={gift.occasion == "birthday"}>
                            Birthday
                          </option>
                          <option value="christmas" selected={gift.occasion == "christmas"}>
                            Christmas
                          </option>
                          <option value="anniversary" selected={gift.occasion == "anniversary"}>
                            Anniversary
                          </option>
                          <option value="wedding" selected={gift.occasion == "wedding"}>
                            Wedding
                          </option>
                          <option value="thank_you" selected={gift.occasion == "thank_you"}>
                            Thank You
                          </option>
                          <option value="other" selected={gift.occasion == "other"}>Other</option>
                        </select>
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                          Date
                        </label>
                        <input
                          type="date"
                          name="gift[date]"
                          value={gift.date && Date.to_iso8601(gift.date)}
                          class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                        />
                      </div>
                    </div>
                    <div class="grid grid-cols-2 gap-3">
                      <div>
                        <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                          Amount
                        </label>
                        <input
                          type="number"
                          name="gift[amount]"
                          value={format_amount(gift.amount)}
                          step="0.01"
                          min="0"
                          class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                          Status
                        </label>
                        <select
                          name="gift[status]"
                          class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                        >
                          <option value="idea" selected={gift.status == "idea"}>Idea</option>
                          <option value="purchased" selected={gift.status == "purchased"}>
                            Purchased
                          </option>
                          <option value="given" selected={gift.status == "given"}>Given</option>
                          <option value="received" selected={gift.status == "received"}>
                            Received
                          </option>
                        </select>
                      </div>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                        Purchase URL
                      </label>
                      <input
                        type="url"
                        name="gift[purchase_url]"
                        value={gift.purchase_url}
                        placeholder="https://..."
                        class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                      />
                    </div>
                  </div>
                  <div class="flex gap-2 mt-3">
                    <button
                      type="submit"
                      class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
                    >
                      Save
                    </button>
                    <button
                      type="button"
                      phx-click="cancel-form"
                      phx-target={@myself}
                      class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-sunken)] hover:text-[var(--color-text-primary)] transition-colors cursor-pointer"
                    >
                      Cancel
                    </button>
                  </div>
                </.form>
              <% else %>
                <%!-- Gift display --%>
                <div class="flex items-start justify-between">
                  <div class="flex items-start gap-3 flex-1">
                    <div class="mt-0.5 flex-shrink-0">
                      <.icon name="hero-gift" class="size-5 text-[var(--color-accent)]" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2 flex-wrap">
                        <p class="text-sm font-medium text-[var(--color-text-primary)]">
                          {gift.name}
                        </p>
                        <span class={[
                          "inline-flex items-center rounded-full px-1.5 py-0.5 text-[10px] font-medium",
                          direction_badge_class(gift.direction)
                        ]}>
                          {String.capitalize(gift.direction || "")}
                        </span>
                        <span class={[
                          "inline-flex items-center rounded-full px-1.5 py-0.5 text-[10px] font-medium",
                          status_badge_class(gift.status)
                        ]}>
                          {String.capitalize(gift.status || "")}
                        </span>
                      </div>
                      <p
                        :if={gift.description}
                        class="text-xs text-[var(--color-text-tertiary)] mt-0.5 line-clamp-2"
                      >
                        {gift.description}
                      </p>
                      <div class="flex items-center gap-2 mt-1 flex-wrap">
                        <span :if={gift.occasion} class="text-xs text-[var(--color-text-tertiary)]">
                          {occasion_label(gift.occasion)}
                        </span>
                        <span :if={gift.date} class="text-xs text-[var(--color-text-tertiary)]">
                          <.date_display date={gift.date} />
                        </span>
                        <span
                          :if={gift.amount}
                          class="text-xs font-medium text-[var(--color-text-primary)]"
                        >
                          ${format_amount(gift.amount)}
                        </span>
                        <a
                          :if={gift.purchase_url}
                          href={gift.purchase_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="text-xs text-[var(--color-accent)] hover:text-[var(--color-accent-hover)] transition-colors"
                        >
                          <.icon name="hero-arrow-top-right-on-square" class="size-3 inline" /> Link
                        </a>
                      </div>
                    </div>
                  </div>
                  <%= if @can_edit do %>
                    <div class="flex items-center gap-1 ms-2 shrink-0">
                      <button
                        phx-click="edit-gift"
                        phx-value-id={gift.id}
                        phx-target={@myself}
                        class="text-[var(--color-text-tertiary)] hover:text-[var(--color-accent)] transition-colors cursor-pointer"
                        title="Edit"
                      >
                        <.icon name="hero-pencil-square" class="size-4" />
                      </button>
                      <button
                        phx-click="delete-gift"
                        phx-value-id={gift.id}
                        phx-target={@myself}
                        data-confirm="Delete this gift? This cannot be undone."
                        class="text-[var(--color-text-tertiary)] hover:text-[var(--color-error)] transition-colors cursor-pointer"
                        title="Delete"
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  <% end %>
                </div>
                <div class="flex items-center justify-between mt-2 text-xs text-[var(--color-text-tertiary)]">
                  <span><.datetime_display datetime={gift.inserted_at} /></span>
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
