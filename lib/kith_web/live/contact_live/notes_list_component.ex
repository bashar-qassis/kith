defmodule KithWeb.ContactLive.NotesListComponent do
  use KithWeb, :live_component

  alias Kith.Contacts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:notes, [])
     |> assign(:editing_note_id, nil)
     |> assign(:show_form, false)}
  end

  @impl true
  def update(assigns, socket) do
    notes = Contacts.list_notes(assigns.contact_id, assigns.current_user_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:notes, notes)
     |> assign_new(:changeset, fn -> Contacts.Note.changeset(%Contacts.Note{}, %{}) end)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_note_id, nil)
     |> assign(:changeset, Contacts.Note.changeset(%Contacts.Note{}, %{}))}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_note_id, nil)}
  end

  def handle_event("save-note", %{"note" => note_params}, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    case Contacts.create_note(contact, socket.assigns.current_user_id, note_params) do
      {:ok, _note} ->
        notes = Contacts.list_notes(socket.assigns.contact_id, socket.assigns.current_user_id)

        {:noreply,
         socket
         |> assign(:notes, notes)
         |> assign(:show_form, false)
         |> put_flash(:info, "Note added.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("edit-note", %{"id" => id}, socket) do
    note =
      Contacts.get_note!(
        socket.assigns.account_id,
        String.to_integer(id),
        socket.assigns.current_user_id
      )

    changeset = Contacts.Note.changeset(note, %{})

    {:noreply,
     socket
     |> assign(:editing_note_id, note.id)
     |> assign(:show_form, false)
     |> assign(:changeset, changeset)}
  end

  def handle_event("update-note", %{"note" => note_params}, socket) do
    note =
      Contacts.get_note!(
        socket.assigns.account_id,
        socket.assigns.editing_note_id,
        socket.assigns.current_user_id
      )

    case Contacts.update_note(note, note_params) do
      {:ok, _note} ->
        notes = Contacts.list_notes(socket.assigns.contact_id, socket.assigns.current_user_id)

        {:noreply,
         socket
         |> assign(:notes, notes)
         |> assign(:editing_note_id, nil)
         |> put_flash(:info, "Note updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    note =
      Contacts.get_note!(
        socket.assigns.account_id,
        String.to_integer(id),
        socket.assigns.current_user_id
      )

    {:ok, _} = Contacts.toggle_note_favorite(note)
    notes = Contacts.list_notes(socket.assigns.contact_id, socket.assigns.current_user_id)
    {:noreply, assign(socket, :notes, notes)}
  end

  def handle_event("delete-note", %{"id" => id}, socket) do
    note =
      Contacts.get_note!(
        socket.assigns.account_id,
        String.to_integer(id),
        socket.assigns.current_user_id
      )

    {:ok, _} = Contacts.delete_note(note)
    notes = Contacts.list_notes(socket.assigns.contact_id, socket.assigns.current_user_id)

    {:noreply,
     socket
     |> assign(:notes, notes)
     |> put_flash(:info, "Note deleted.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Notes</h2>
        <%= if @can_edit do %>
          <button phx-click="show-form" phx-target={@myself} class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Note
          </button>
        <% end %>
      </div>

      <%!-- Add note form --%>
      <%= if @show_form do %>
        <div class="card bg-base-100 shadow-sm mb-4">
          <div class="card-body p-4">
            <.form for={%{}} phx-submit="save-note" phx-target={@myself}>
              <div id={"trix-new-note-#{@contact_id}"} phx-hook="TrixEditor" data-input="note[body]">
                <input type="hidden" name="note[body]" value="" />
                <trix-editor class="trix-content min-h-[100px] prose prose-sm max-w-none border rounded-lg p-2 bg-base-100">
                </trix-editor>
              </div>
              <div class="form-control mt-2">
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name="note[is_private]"
                    value="true"
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text flex items-center gap-1">
                    <.icon name="hero-lock-closed" class="size-4" /> Private (only visible to you)
                  </span>
                </label>
              </div>
              <div class="flex gap-2 mt-3">
                <button type="submit" class="btn btn-sm btn-primary">Save</button>
                <button
                  type="button"
                  phx-click="cancel-form"
                  phx-target={@myself}
                  class="btn btn-sm btn-ghost"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- Notes list --%>
      <%= if @notes == [] do %>
        <p class="text-base-content/60">No notes yet.</p>
      <% end %>

      <div class="space-y-3">
        <%= for note <- @notes do %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <%= if @editing_note_id == note.id do %>
                <%!-- Inline edit form --%>
                <.form for={%{}} phx-submit="update-note" phx-target={@myself}>
                  <div id={"trix-edit-note-#{note.id}"} phx-hook="TrixEditor" data-input="note[body]">
                    <input type="hidden" name="note[body]" value={note.body} />
                    <trix-editor class="trix-content min-h-[100px] prose prose-sm max-w-none border rounded-lg p-2 bg-base-100">
                    </trix-editor>
                  </div>
                  <div class="flex gap-2 mt-3">
                    <button type="submit" class="btn btn-sm btn-primary">Save</button>
                    <button
                      type="button"
                      phx-click="cancel-form"
                      phx-target={@myself}
                      class="btn btn-sm btn-ghost"
                    >
                      Cancel
                    </button>
                  </div>
                </.form>
              <% else %>
                <%!-- Note display --%>
                <div class="flex items-start justify-between">
                  <div class="prose prose-sm max-w-none flex-1">
                    {raw(note.body)}
                  </div>
                  <div class="flex items-center gap-1 ml-2 shrink-0">
                    <%= if note.is_private do %>
                      <span class="tooltip" data-tip="Private note">
                        <.icon name="hero-lock-closed" class="size-4 text-warning" />
                      </span>
                    <% end %>
                    <button
                      phx-click="toggle-favorite"
                      phx-value-id={note.id}
                      phx-target={@myself}
                      class="btn btn-ghost btn-xs"
                    >
                      <.icon
                        name={if note.favorite, do: "hero-star-solid", else: "hero-star"}
                        class={["size-4", note.favorite && "text-warning"]}
                      />
                    </button>
                  </div>
                </div>
                <div class="flex items-center justify-between mt-2 text-xs text-base-content/50">
                  <span>{Calendar.strftime(note.inserted_at, "%b %d, %Y at %I:%M %p")}</span>
                  <%= if @can_edit do %>
                    <div class="flex gap-2">
                      <button
                        phx-click="edit-note"
                        phx-value-id={note.id}
                        phx-target={@myself}
                        class="link link-hover"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="delete-note"
                        phx-value-id={note.id}
                        phx-target={@myself}
                        data-confirm="Delete this note? This cannot be undone."
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
