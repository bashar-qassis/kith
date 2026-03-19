defmodule KithWeb.ContactLive.ImmichReview do
  use KithWeb, :live_view

  alias Kith.Contacts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    account_id = scope.account.id

    # Editor and admin only
    unless scope.user.role in ["admin", "editor"] do
      raise KithWeb.ForbiddenError
    end

    contact =
      Contacts.get_contact!(account_id, String.to_integer(id))

    candidates = Contacts.list_pending_candidates(account_id, contact.id)

    {:ok,
     socket
     |> assign(:page_title, "Immich Review — #{contact.display_name}")
     |> assign(:account_id, account_id)
     |> assign(:contact, contact)
     |> assign(:candidates, candidates)}
  end

  @impl true
  def handle_event("accept", %{"candidate-id" => candidate_id}, socket) do
    candidate = Enum.find(socket.assigns.candidates, &(to_string(&1.id) == candidate_id))

    if candidate do
      contact = socket.assigns.contact

      {:ok, updated_contact} =
        Contacts.confirm_immich_link(
          contact,
          candidate.immich_photo_id,
          "#{candidate.immich_server_url}/api/people/#{candidate.immich_photo_id}"
        )

      {:noreply,
       socket
       |> assign(:contact, updated_contact)
       |> assign(:candidates, [])
       |> put_flash(:info, "Immich link confirmed for #{contact.display_name}")}
    else
      {:noreply, put_flash(socket, :error, "Candidate not found")}
    end
  end

  def handle_event("reject", %{"candidate-id" => candidate_id}, socket) do
    candidate = Enum.find(socket.assigns.candidates, &(to_string(&1.id) == candidate_id))

    if candidate do
      Contacts.reject_immich_candidate(candidate)
      candidates = Contacts.list_pending_candidates(socket.assigns.account_id, socket.assigns.contact.id)

      {:noreply,
       socket
       |> assign(:candidates, candidates)
       |> put_flash(:info, "Candidate rejected")}
    else
      {:noreply, put_flash(socket, :error, "Candidate not found")}
    end
  end

  def handle_event("reject-all", _params, socket) do
    account_id = socket.assigns.account_id
    contact = socket.assigns.contact

    Enum.each(socket.assigns.candidates, fn candidate ->
      Contacts.reject_immich_candidate(candidate)
    end)

    candidates = Contacts.list_pending_candidates(account_id, contact.id)

    {:noreply,
     socket
     |> assign(:candidates, candidates)
     |> put_flash(:info, "All candidates rejected")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <.header>
        Immich Photo Review
        <:subtitle>Review photo suggestions for {@contact.display_name}</:subtitle>
      </.header>

      <div :if={@candidates == []} class="mt-8 text-center py-12 bg-gray-50 rounded-lg">
        <p class="text-gray-500 text-lg">No photo suggestions available</p>
        <.link navigate={~p"/contacts/#{@contact.id}"} class="text-blue-600 hover:underline mt-2 inline-block">
          Back to contact
        </.link>
      </div>

      <div :if={@candidates != []} class="mt-8">
        <div class="flex justify-between items-center mb-4">
          <p class="text-sm text-gray-600">{length(@candidates)} pending suggestion(s)</p>
          <button phx-click="reject-all" data-confirm="Reject all candidates?"
            class="text-sm text-red-600 hover:text-red-800">
            Reject All
          </button>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <div :for={candidate <- @candidates}
            class="bg-white border rounded-lg overflow-hidden shadow-sm">
            <div class="aspect-square bg-gray-100 flex items-center justify-center">
              <img src={candidate.thumbnail_url}
                alt={"Immich suggestion"}
                class="object-cover w-full h-full"
                loading="lazy" />
            </div>
            <div class="p-4">
              <p class="text-sm text-gray-600 mb-3">
                Suggested {Calendar.strftime(candidate.suggested_at, "%b %d, %Y")}
              </p>
              <div class="flex gap-2">
                <button phx-click="accept" phx-value-candidate-id={candidate.id}
                  class="flex-1 bg-green-600 text-white text-sm py-2 px-3 rounded hover:bg-green-700">
                  Accept
                </button>
                <button phx-click="reject" phx-value-candidate-id={candidate.id}
                  class="flex-1 bg-red-100 text-red-700 text-sm py-2 px-3 rounded hover:bg-red-200">
                  Reject
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
