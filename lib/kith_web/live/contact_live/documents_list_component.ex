defmodule KithWeb.ContactLive.DocumentsListComponent do
  use KithWeb, :live_component

  alias Kith.Contacts
  alias Kith.Storage

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:documents, [])
     |> allow_upload(:document,
       accept: :any,
       max_entries: 3,
       max_file_size: 50_000_000
     )}
  end

  @impl true
  def update(assigns, socket) do
    documents = Contacts.list_documents(assigns.contact_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:documents, documents)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    uploaded_docs =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        key = "contacts/#{contact.id}/documents/#{entry.uuid}-#{entry.client_name}"
        {:ok, _} = Storage.upload(path, key)

        {:ok, doc} =
          Contacts.create_document(contact, %{
            file_name: entry.client_name,
            storage_key: key,
            file_size: entry.client_size,
            content_type: entry.client_type
          })

        {:ok, doc}
      end)

    if uploaded_docs != [] do
      documents = Contacts.list_documents(socket.assigns.contact_id)

      {:noreply,
       socket
       |> assign(:documents, documents)
       |> put_flash(:info, "#{length(uploaded_docs)} document(s) uploaded.")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    doc = Contacts.get_document!(socket.assigns.account_id, String.to_integer(id))
    Storage.delete(doc.storage_key)
    {:ok, _} = Contacts.delete_document(doc)
    documents = Contacts.list_documents(socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:documents, documents)
     |> put_flash(:info, "Document deleted.")}
  end

  defp format_size(nil), do: "—"
  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp file_icon(content_type) do
    cond do
      String.starts_with?(content_type || "", "image/") ->
        "hero-photo"

      String.contains?(content_type || "", "pdf") ->
        "hero-document-text"

      String.contains?(content_type || "", "spreadsheet") or
          String.contains?(content_type || "", "csv") ->
        "hero-table-cells"

      true ->
        "hero-document"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Documents</h2>
      </div>

      <%!-- Upload form --%>
      <%= if @can_edit do %>
        <form
          id={"doc-upload-#{@contact_id}"}
          phx-submit="upload"
          phx-change="validate"
          phx-target={@myself}
          class="mb-4"
        >
          <div class="flex items-center gap-3">
            <.live_file_input
              upload={@uploads.document}
              class="file-input file-input-bordered file-input-sm"
            />
            <button
              type="submit"
              class="btn btn-sm btn-primary"
              disabled={@uploads.document.entries == []}
            >
              Upload
            </button>
          </div>
          <%= for entry <- @uploads.document.entries do %>
            <div class="text-sm mt-1 flex items-center gap-2">
              <span>{entry.client_name}</span>
              <progress value={entry.progress} max="100" class="progress progress-primary w-24">
                {entry.progress}%
              </progress>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                phx-target={@myself}
                class="text-error text-xs"
              >
                &times;
              </button>
            </div>
            <%= for err <- upload_errors(@uploads.document, entry) do %>
              <p class="text-error text-xs">{error_to_string(err)}</p>
            <% end %>
          <% end %>
        </form>
      <% end %>

      <%= if @documents == [] do %>
        <p class="text-base-content/60">No documents yet.</p>
      <% end %>

      <div class="space-y-2">
        <%= for doc <- @documents do %>
          <div class="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-base-200/50">
            <div class="flex items-center gap-3">
              <.icon name={file_icon(doc.content_type)} class="size-5 text-base-content/40" />
              <div>
                <a
                  href={Storage.url(doc.storage_key)}
                  target="_blank"
                  class="link link-hover text-sm font-medium"
                >
                  {doc.file_name}
                </a>
                <div class="text-xs text-base-content/50">
                  {format_size(doc.file_size)} &middot; {Calendar.strftime(
                    doc.inserted_at,
                    "%b %d, %Y"
                  )}
                </div>
              </div>
            </div>
            <%= if @can_edit do %>
              <button
                phx-click="delete"
                phx-value-id={doc.id}
                phx-target={@myself}
                data-confirm="Delete this document?"
                class="link link-hover text-error text-xs"
              >
                Delete
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File too large (max 50MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max 3)"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(err), do: to_string(err)
end
