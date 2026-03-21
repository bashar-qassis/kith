defmodule KithWeb.ContactLive.Merge do
  use KithWeb, :live_view

  alias Kith.Contacts
  alias Kith.Policy

  @mergeable_fields ~w(first_name last_name nickname birthdate description occupation company avatar)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Merge Contacts")
     |> assign(:contact_a, nil)
     |> assign(:contact_b, nil)
     |> assign(:step, 1)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:field_choices, default_field_choices())
     |> assign(:preview, nil)
     |> assign(:merging, false)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    scope = socket.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    unless Policy.can?(user, :update, :contact) do
      {:noreply,
       socket
       |> put_flash(:error, "You don't have permission to merge contacts")
       |> push_navigate(to: ~p"/contacts")}
    else
      contact_a = Contacts.get_contact(account_id, id, preload: [:tags, :gender])

      if is_nil(contact_a) do
        {:noreply,
         socket
         |> put_flash(:error, "Contact not found")
         |> push_navigate(to: ~p"/contacts")}
      else
        {:noreply,
         socket
         |> assign(:page_title, "Merge #{contact_a.display_name || "Contact"}")
         |> assign(:contact_a, contact_a)
         |> assign(:contact_b, nil)
         |> assign(:step, 1)
         |> assign(:search_query, "")
         |> assign(:search_results, [])
         |> assign(:field_choices, default_field_choices())
         |> assign(:preview, nil)
         |> assign(:merging, false)}
      end
    end
  end

  # ── Step 1: Search ─────────────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    scope = socket.assigns.current_scope
    contact_a = socket.assigns.contact_a

    results =
      if String.length(query) >= 2 do
        Contacts.search_contacts(scope.account.id, query)
        |> Enum.reject(&(&1.id == contact_a.id))
        |> Enum.take(10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  def handle_event("select-contact", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    contact_b =
      Contacts.get_contact(scope.account.id, String.to_integer(id), preload: [:tags, :gender])

    if contact_b do
      {:noreply,
       socket
       |> assign(:contact_b, contact_b)
       |> assign(:step, 2)}
    else
      {:noreply, put_flash(socket, :error, "Contact not found")}
    end
  end

  # ── Step 2: Field Choices ──────────────────────────────────────────────

  def handle_event("choose-field", %{"field" => field, "source" => source}, socket) do
    choices = Map.put(socket.assigns.field_choices, field, source)
    {:noreply, assign(socket, :field_choices, choices)}
  end

  def handle_event("go-to-preview", _params, socket) do
    contact_a = socket.assigns.contact_a
    contact_b = socket.assigns.contact_b

    case Contacts.merge_preview(contact_a.id, contact_b.id) do
      {:ok, preview} ->
        {:noreply,
         socket
         |> assign(:preview, preview)
         |> assign(:step, 3)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Preview failed: #{inspect(reason)}")}
    end
  end

  # ── Step 3: Preview ────────────────────────────────────────────────────

  def handle_event("confirm-merge", _params, socket) do
    {:noreply, assign(socket, :step, 4)}
  end

  # ── Step 4: Execute ────────────────────────────────────────────────────

  def handle_event("execute-merge", _params, socket) do
    contact_a = socket.assigns.contact_a
    contact_b = socket.assigns.contact_b
    field_choices = socket.assigns.field_choices

    socket = assign(socket, :merging, true)

    case Contacts.merge_contacts(contact_a.id, contact_b.id, field_choices) do
      {:ok, _result} ->
        # Log the merge
        scope = socket.assigns.current_scope

        Kith.AuditLogs.log_event(scope.account.id, scope.user, :contact_merged,
          contact_id: contact_a.id,
          contact_name: contact_a.display_name,
          metadata: %{
            survivor_id: contact_a.id,
            survivor_name: contact_a.display_name,
            non_survivor_id: contact_b.id,
            non_survivor_name: contact_b.display_name,
            field_choices: field_choices,
            sub_entities_moved: socket.assigns.preview
          }
        )

        {:noreply,
         socket
         |> put_flash(:info, "Contacts merged successfully")
         |> redirect(to: ~p"/contacts/#{contact_a.id}")}

      {:error, step, changeset, _changes} ->
        {:noreply,
         socket
         |> assign(:merging, false)
         |> put_flash(:error, "Merge failed at step #{inspect(step)}: #{inspect(changeset)}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:merging, false)
         |> put_flash(:error, "Merge failed: #{inspect(reason)}")}
    end
  end

  # ── Navigation ─────────────────────────────────────────────────────────

  def handle_event("back", _params, socket) do
    new_step = max(socket.assigns.step - 1, 1)
    {:noreply, assign(socket, :step, new_step)}
  end

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :mergeable_fields, @mergeable_fields)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="max-w-4xl mx-auto px-4 py-8">
        <.section_header title="Merge Contacts">
          Step {@step} of 4 — {step_label(@step)}
        </.section_header>

        <%!-- Step indicator --%>
        <div class="mt-4 flex gap-2">
          <div
            :for={s <- 1..4}
            class={[
              "h-1 flex-1 rounded",
              if(s <= @step, do: "bg-blue-600", else: "bg-gray-200")
            ]}
          >
          </div>
        </div>

        <%!-- Step 1: Search --%>
        <div :if={@step == 1 && @contact_a} class="mt-6">
          <.card>
            <div class="p-6">
              <div class="flex items-center gap-4 mb-4">
                <.avatar name={@contact_a.display_name} src={@contact_a.avatar} size={:md} />
                <div>
                  <p class="text-sm text-gray-600">Merging from:</p>
                  <span class="font-semibold">{@contact_a.display_name}</span>
                </div>
              </div>

              <p class="text-sm text-gray-600 mb-4">
                Search for the contact to merge with:
              </p>

              <form phx-change="search" phx-submit="search">
                <input
                  type="text"
                  name="query"
                  value={@search_query}
                  placeholder="Search by name, email, or phone..."
                  phx-debounce="300"
                  autofocus
                  class="w-full border-gray-300 rounded-md shadow-sm"
                />
              </form>

              <div :if={@search_results != []} class="mt-4 border rounded-md divide-y">
                <button
                  :for={contact <- @search_results}
                  phx-click="select-contact"
                  phx-value-id={contact.id}
                  class="w-full text-start px-4 py-3 hover:bg-gray-50 flex items-center justify-between"
                >
                  <div>
                    <span class="font-medium">{contact.display_name}</span>
                    <span :if={contact.company} class="text-sm text-gray-500 ms-2">
                      {contact.company}
                    </span>
                  </div>
                  <span class="text-xs text-gray-400">Select</span>
                </button>
              </div>

              <.empty_state
                :if={@search_query != "" && @search_results == []}
                icon="hero-magnifying-glass"
                title="No matches"
                message="No matching contacts found."
              />
            </div>
          </.card>
        </div>

        <%!-- Step 2: Field Selection --%>
        <div :if={@step == 2 && @contact_b} class="mt-6">
          <.card>
            <div class="p-6">
              <div class="grid grid-cols-3 gap-4 mb-4 text-sm font-semibold text-gray-700">
                <div>Field</div>
                <div class="flex items-center gap-2">
                  <.avatar name={@contact_a.display_name} src={@contact_a.avatar} size={:sm} />
                  {@contact_a.display_name} (A)
                </div>
                <div class="flex items-center gap-2">
                  <.avatar name={@contact_b.display_name} src={@contact_b.avatar} size={:sm} />
                  {@contact_b.display_name} (B)
                </div>
              </div>

              <div
                :for={field <- @mergeable_fields}
                class="grid grid-cols-3 gap-4 py-3 border-t items-center"
              >
                <div class="text-sm font-medium text-gray-600">{humanize(field)}</div>
                <button
                  phx-click="choose-field"
                  phx-value-field={field}
                  phx-value-source="survivor"
                  class={[
                    "text-start text-sm px-3 py-2 rounded border",
                    if(Map.get(@field_choices, field) == "survivor",
                      do: "border-blue-500 bg-blue-50 text-blue-700",
                      else: "border-gray-200 hover:border-gray-300"
                    )
                  ]}
                >
                  {field_value(@contact_a, field) || "-"}
                </button>
                <button
                  phx-click="choose-field"
                  phx-value-field={field}
                  phx-value-source="non_survivor"
                  class={[
                    "text-start text-sm px-3 py-2 rounded border",
                    if(Map.get(@field_choices, field) == "non_survivor",
                      do: "border-blue-500 bg-blue-50 text-blue-700",
                      else: "border-gray-200 hover:border-gray-300"
                    )
                  ]}
                >
                  {field_value(@contact_b, field) || "-"}
                </button>
              </div>

              <div class="mt-6 flex gap-3">
                <button
                  phx-click="back"
                  class="bg-gray-100 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-200 text-sm"
                >
                  Back
                </button>
                <button
                  phx-click="go-to-preview"
                  class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 text-sm"
                >
                  Preview Merge
                </button>
              </div>
            </div>
          </.card>
        </div>

        <%!-- Step 3: Dry-run Preview --%>
        <div :if={@step == 3 && @preview} class="mt-6">
          <.card>
            <div class="p-6">
              <h3 class="text-lg font-semibold mb-4">Merge Preview</h3>
              <p class="text-sm text-gray-600 mb-4">
                This is what will happen when you merge
                <span class="font-semibold">{@contact_b.display_name}</span>
                into <span class="font-semibold">{@contact_a.display_name}</span>:
              </p>

              <ul class="space-y-2 text-sm">
                <li :if={@preview.notes > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {@preview.notes} notes will be combined
                </li>
                <li :if={@preview.activities > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {@preview.activities} activities will be combined
                </li>
                <li :if={@preview.calls > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {@preview.calls} calls will be combined
                </li>
                <li :if={@preview.life_events > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {@preview.life_events} life events will be combined
                </li>
                <li :if={@preview.addresses > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {@preview.addresses} addresses will be combined
                </li>
                <li :if={@preview.contact_fields > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {@preview.contact_fields} contact fields will be combined
                </li>
                <li :if={@preview.reminders > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {@preview.reminders} reminders will be combined
                </li>
                <li :if={@preview.tags_to_merge > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-green-500 rounded-full"></span>
                  {@preview.tags_to_merge} new tags will be added
                </li>
                <li :if={@preview.tags_duplicate > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-gray-400 rounded-full"></span>
                  {@preview.tags_duplicate} duplicate tags will be removed
                </li>
                <li :if={@preview.relationships_to_dedup > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-amber-500 rounded-full"></span>
                  {@preview.relationships_to_dedup} duplicate relationships will be removed
                </li>
                <li :if={@preview.relationships_to_remap > 0} class="flex items-center gap-2">
                  <span class="w-2 h-2 bg-blue-500 rounded-full"></span>
                  {@preview.relationships_to_remap} relationships will be transferred
                </li>
              </ul>

              <div class="mt-4 p-3 bg-amber-50 border border-amber-200 rounded text-sm text-amber-800">
                {@contact_b.display_name} will be moved to trash (recoverable for 30 days).
              </div>

              <div class="mt-6 flex gap-3">
                <button
                  phx-click="back"
                  class="bg-gray-100 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-200 text-sm"
                >
                  Back
                </button>
                <button
                  phx-click="confirm-merge"
                  class="bg-red-600 text-white px-4 py-2 rounded-md hover:bg-red-700 text-sm"
                >
                  Confirm Merge
                </button>
              </div>
            </div>
          </.card>
        </div>

        <%!-- Step 4: Confirm & Execute --%>
        <div :if={@step == 4} class="mt-6">
          <.card>
            <div class="p-6 text-center">
              <h3 class="text-lg font-semibold mb-4">Final Confirmation</h3>
              <p class="text-gray-600 mb-6">
                This action cannot be easily undone. Are you sure you want to merge
                <span class="font-semibold">{@contact_b.display_name}</span>
                into <span class="font-semibold">{@contact_a.display_name}</span>?
              </p>

              <div class="flex justify-center gap-3">
                <button
                  phx-click="back"
                  disabled={@merging}
                  class="bg-gray-100 text-gray-700 px-6 py-2 rounded-md hover:bg-gray-200 text-sm disabled:opacity-50"
                >
                  Go Back
                </button>
                <button
                  phx-click="execute-merge"
                  disabled={@merging}
                  class="bg-red-600 text-white px-6 py-2 rounded-md hover:bg-red-700 text-sm disabled:opacity-50"
                >
                  {if @merging, do: "Merging...", else: "Merge Contacts"}
                </button>
              </div>
            </div>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp step_label(1), do: "Select contact"
  defp step_label(2), do: "Choose fields"
  defp step_label(3), do: "Preview"
  defp step_label(4), do: "Confirm"

  defp default_field_choices do
    @mergeable_fields
    |> Enum.map(&{&1, "survivor"})
    |> Map.new()
  end

  defp field_value(contact, field) do
    value = Map.get(contact, String.to_existing_atom(field))

    case value do
      %Date{} = d -> Date.to_iso8601(d)
      nil -> nil
      v -> to_string(v)
    end
  end

  defp humanize(field) do
    field
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
