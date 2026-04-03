defmodule KithWeb.ContactLive.FirstMetComponent do
  @moduledoc """
  Slide-over panel component for editing "How We Met" data on a contact.

  Displays a read-only sidebar section (or empty state CTA when no data exists).
  Clicking Edit/Add opens a slide-over panel from the right with a dark backdrop.
  """

  use KithWeb, :live_component

  alias Kith.Contacts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_panel, false)
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])
     |> assign(:selected_through, nil)}
  end

  @impl true
  def update(assigns, socket) do
    selected_through =
      if socket.assigns[:selected_through] do
        socket.assigns.selected_through
      else
        assigns.contact.first_met_through
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_through, selected_through)}
  end

  @impl true
  def handle_event("open-panel", _params, socket) do
    contact = socket.assigns.contact
    selected = contact.first_met_through

    {:noreply,
     socket
     |> assign(:show_panel, true)
     |> assign(:selected_through, selected)
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])}
  end

  def handle_event("close-panel", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_panel, false)
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])}
  end

  def handle_event("search-contacts", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        socket.assigns.account_id
        |> Contacts.search_contacts(query)
        |> Enum.reject(&(&1.id == socket.assigns.contact_id))
        |> Enum.take(10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:contact_search, query)
     |> assign(:contact_results, results)}
  end

  def handle_event("select-contact", %{"id" => id}, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, String.to_integer(id))

    {:noreply,
     socket
     |> assign(:selected_through, contact)
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])}
  end

  def handle_event("clear-through", _params, socket) do
    {:noreply, assign(socket, :selected_through, nil)}
  end

  def handle_event("save", params, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    first_met_params = params["first_met"] || %{}

    year_unknown = first_met_params["first_met_year_unknown"] == "true"

    attrs = %{
      "first_met_at" => parse_date(first_met_params["first_met_at"]),
      "first_met_year_unknown" => year_unknown,
      "first_met_where" => first_met_params["first_met_where"],
      "first_met_additional_info" => first_met_params["first_met_additional_info"],
      "first_met_through_id" =>
        if(socket.assigns.selected_through, do: socket.assigns.selected_through.id)
    }

    case Contacts.update_contact(contact, attrs) do
      {:ok, updated} ->
        send(self(), {:first_met_updated, updated})

        {:noreply,
         socket
         |> assign(:show_panel, false)
         |> put_flash(:info, "How we met updated.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save.")}
    end
  end

  def handle_event("clear", _params, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    attrs = %{
      "first_met_at" => nil,
      "first_met_year_unknown" => false,
      "first_met_where" => nil,
      "first_met_additional_info" => nil,
      "first_met_through_id" => nil
    }

    case Contacts.update_contact(contact, attrs) do
      {:ok, updated} ->
        send(self(), {:first_met_updated, updated})

        {:noreply,
         socket
         |> assign(:show_panel, false)
         |> assign(:selected_through, nil)
         |> put_flash(:info, "How we met cleared.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to clear.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Sidebar read state --%>
      <div class="flex justify-between items-center mb-2">
        <span class="text-sm font-medium text-[var(--color-text-primary)]">How We Met</span>
        <button
          :if={@can_edit && has_data?(@contact)}
          phx-click="open-panel"
          phx-target={@myself}
          class="inline-flex items-center gap-1 rounded-[var(--radius-md)] border border-[var(--color-border-subtle)] px-2 py-1 text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] hover:border-[var(--color-border)] transition-colors"
        >
          <.icon name="hero-pencil" class="size-3" /> Edit
        </button>
      </div>

      <%= if has_data?(@contact) do %>
        <dl class="space-y-2 text-sm">
          <div :if={@contact.first_met_at} class="flex justify-between">
            <dt class="text-[var(--color-text-tertiary)]">Date</dt>
            <dd class="text-[var(--color-text-primary)]">
              <KithUI.date_display
                date={@contact.first_met_at}
                year_unknown={@contact.first_met_year_unknown}
              />
            </dd>
          </div>

          <div :if={@contact.first_met_where} class="flex justify-between">
            <dt class="text-[var(--color-text-tertiary)]">Where</dt>
            <dd class="text-[var(--color-text-primary)]">{@contact.first_met_where}</dd>
          </div>

          <div :if={@contact.first_met_through} class="flex justify-between">
            <dt class="text-[var(--color-text-tertiary)]">Through</dt>
            <dd>
              <.link
                navigate={~p"/contacts/#{@contact.first_met_through.id}"}
                class="text-[var(--color-accent)] hover:text-[var(--color-accent-hover)] transition-colors"
              >
                {@contact.first_met_through.display_name}
              </.link>
            </dd>
          </div>

          <div :if={@contact.first_met_additional_info}>
            <dt class="text-[var(--color-text-tertiary)]">Notes</dt>
            <dd class="text-[var(--color-text-secondary)] mt-0.5 leading-relaxed">
              {@contact.first_met_additional_info}
            </dd>
          </div>
        </dl>
      <% else %>
        <%!-- Empty state --%>
        <div :if={@can_edit} class="text-center py-4">
          <div class="text-2xl opacity-40 mb-2">🤝</div>
          <p class="text-sm text-[var(--color-text-tertiary)] mb-3">
            Remember how you first connected
          </p>
          <button
            phx-click="open-panel"
            phx-target={@myself}
            class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] border border-[var(--color-accent)] px-3 py-1.5 text-sm font-medium text-[var(--color-accent)] hover:bg-[var(--color-accent)]/10 transition-colors"
          >
            + Add how we met
          </button>
        </div>
      <% end %>

      <%!-- Slide-over panel --%>
      <%= if @show_panel do %>
        <div
          id={"first-met-backdrop-#{@contact.id}"}
          class="fixed inset-0 z-40 bg-black/50 transition-opacity"
          phx-click="close-panel"
          phx-target={@myself}
        >
        </div>
        <div
          id={"first-met-panel-#{@contact.id}"}
          class="fixed inset-y-0 right-0 z-50 w-full max-w-[440px] bg-[var(--color-surface)] shadow-2xl overflow-y-auto"
          phx-window-keydown="close-panel"
          phx-key="Escape"
          phx-target={@myself}
        >
          <%!-- Panel header --%>
          <div class="flex items-center justify-between px-5 py-4 border-b border-[var(--color-border-subtle)]">
            <div>
              <h3 class="text-base font-semibold text-[var(--color-text-primary)]">How We Met</h3>
              <p class="text-xs text-[var(--color-text-tertiary)] mt-0.5">
                Record how you first connected
              </p>
            </div>
            <button
              phx-click="close-panel"
              phx-target={@myself}
              class="text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] transition-colors p-1"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <%!-- Panel body --%>
          <.form for={%{}} phx-submit="save" phx-target={@myself} class="p-5 space-y-5">
            <%!-- When section --%>
            <div class="rounded-[var(--radius-lg)] bg-[var(--color-surface-elevated)] p-4">
              <div class="text-xs font-semibold text-[var(--color-text-tertiary)] mb-3 flex items-center gap-1.5">
                <.icon name="hero-calendar" class="size-3.5" /> When
              </div>
              <div>
                <label class="block text-xs text-[var(--color-text-tertiary)] mb-1">Date</label>
                <input
                  type="date"
                  name="first_met[first_met_at]"
                  value={format_date(@contact.first_met_at)}
                  class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
                />
              </div>
              <label class="flex items-center gap-2 mt-2 text-sm text-[var(--color-text-tertiary)] cursor-pointer">
                <input
                  type="checkbox"
                  name="first_met[first_met_year_unknown]"
                  value="true"
                  checked={@contact.first_met_year_unknown}
                  class="rounded border-[var(--color-border)]"
                /> I don't remember the exact year
              </label>
            </div>

            <%!-- Where section --%>
            <div class="rounded-[var(--radius-lg)] bg-[var(--color-surface-elevated)] p-4">
              <div class="text-xs font-semibold text-[var(--color-text-tertiary)] mb-3 flex items-center gap-1.5">
                <.icon name="hero-map-pin" class="size-3.5" /> Where
              </div>
              <input
                type="text"
                name="first_met[first_met_where]"
                value={@contact.first_met_where}
                placeholder="e.g., College, Conference, Party..."
                class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
              />
            </div>

            <%!-- Introduced by section --%>
            <div class="rounded-[var(--radius-lg)] bg-[var(--color-surface-elevated)] p-4">
              <div class="text-xs font-semibold text-[var(--color-text-tertiary)] mb-3 flex items-center gap-1.5">
                <.icon name="hero-user" class="size-3.5" /> Introduced by
              </div>

              <%= if @selected_through do %>
                <div class="flex items-center gap-2 rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2.5 py-1.5">
                  <KithUI.avatar
                    name={@selected_through.display_name}
                    size={:sm}
                  />
                  <span class="text-sm text-[var(--color-text-primary)] flex-1">
                    {@selected_through.display_name}
                  </span>
                  <button
                    type="button"
                    phx-click="clear-through"
                    phx-target={@myself}
                    class="text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] transition-colors"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              <% else %>
                <div class="relative">
                  <input
                    type="text"
                    value={@contact_search}
                    placeholder="Search contacts..."
                    phx-keyup="search-contacts"
                    phx-target={@myself}
                    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] pl-8 pr-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
                    autocomplete="off"
                  />
                  <.icon
                    name="hero-magnifying-glass"
                    class="size-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--color-text-disabled)]"
                  />
                </div>

                <%= if @contact_results != [] do %>
                  <div class="mt-1 rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] max-h-40 overflow-y-auto">
                    <button
                      :for={result <- @contact_results}
                      type="button"
                      phx-click="select-contact"
                      phx-value-id={result.id}
                      phx-target={@myself}
                      class="w-full flex items-center gap-2 px-3 py-2 text-left hover:bg-[var(--color-surface-elevated)] transition-colors"
                    >
                      <KithUI.avatar name={result.display_name} size={:sm} />
                      <span class="text-sm text-[var(--color-text-primary)]">
                        {result.display_name}
                      </span>
                    </button>
                  </div>
                <% end %>
              <% end %>
            </div>

            <%!-- Story section --%>
            <div class="rounded-[var(--radius-lg)] bg-[var(--color-surface-elevated)] p-4">
              <div class="text-xs font-semibold text-[var(--color-text-tertiary)] mb-3 flex items-center gap-1.5">
                <.icon name="hero-pencil-square" class="size-3.5" /> The story
              </div>
              <textarea
                name="first_met[first_met_additional_info]"
                rows="4"
                placeholder="How did you meet? Any memorable details..."
                class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150 resize-vertical"
              >{@contact.first_met_additional_info}</textarea>
            </div>

            <%!-- Actions --%>
            <div class="flex gap-2 pt-2">
              <button
                type="submit"
                class="flex-1 rounded-[var(--radius-md)] bg-[var(--color-accent)] px-4 py-2 text-sm font-medium text-white hover:bg-[var(--color-accent-hover)] transition-colors"
              >
                Save
              </button>
              <button
                type="button"
                phx-click="close-panel"
                phx-target={@myself}
                class="flex-1 rounded-[var(--radius-md)] border border-[var(--color-border)] px-4 py-2 text-sm text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] transition-colors"
              >
                Cancel
              </button>
            </div>

            <%!-- Clear link --%>
            <div :if={has_data?(@contact)} class="text-center">
              <button
                type="button"
                phx-click="clear"
                phx-target={@myself}
                class="text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-error)] transition-colors"
              >
                Clear all "how we met" data
              </button>
            </div>
          </.form>
        </div>
      <% end %>
    </div>
    """
  end

  defp has_data?(contact) do
    contact.first_met_at != nil or
      contact.first_met_where not in [nil, ""] or
      contact.first_met_through_id != nil or
      contact.first_met_additional_info not in [nil, ""]
  end

  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(_), do: ""

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
