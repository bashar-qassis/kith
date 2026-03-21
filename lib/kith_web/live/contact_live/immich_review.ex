defmodule KithWeb.ContactLive.ImmichReview do
  use KithWeb, :live_view

  alias Kith.Contacts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Immich Review")
     |> assign(:contact, nil)
     |> assign(:candidates, [])
     |> assign(:account_id, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    scope = socket.assigns.current_scope
    account_id = scope.account.id

    unless scope.user.role in ["admin", "editor"] do
      raise KithWeb.ForbiddenError
    end

    contact = Contacts.get_contact!(account_id, String.to_integer(id))
    candidates = Contacts.list_pending_candidates(account_id, contact.id)

    {:noreply,
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

      candidates =
        Contacts.list_pending_candidates(socket.assigns.account_id, socket.assigns.contact.id)

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
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="max-w-4xl mx-auto space-y-6">
        <div>
          <h1 class="text-2xl font-semibold text-[var(--color-text-primary)] tracking-tight">Immich Photo Review</h1>
          <p class="text-sm text-[var(--color-text-tertiary)] mt-1">
            Review photo suggestions for {@contact && @contact.display_name}
          </p>
        </div>

        <div :if={@contact}>
          <UI.card>
            <div class="flex items-center gap-4">
              <KithUI.avatar name={@contact.display_name} size={:lg} />
              <div>
                <h3 class="text-lg font-semibold text-[var(--color-text-primary)]">{@contact.display_name}</h3>
                <p class="text-sm text-[var(--color-text-tertiary)]">
                  {length(@candidates)} pending suggestion(s)
                </p>
              </div>
            </div>
          </UI.card>

          <KithUI.empty_state
            :if={@candidates == []}
            icon="hero-photo"
            title="No photo suggestions"
            message="There are no pending Immich photo suggestions for this contact."
          >
            <:actions>
              <UI.button variant="secondary" size="sm" navigate={~p"/contacts/#{@contact.id}"}>
                Back to contact
              </UI.button>
            </:actions>
          </KithUI.empty_state>

          <div :if={@candidates != []} class="mt-6">
            <div class="flex justify-between items-center mb-4">
              <p class="text-sm text-[var(--color-text-secondary)]">{length(@candidates)} pending suggestion(s)</p>
              <button
                phx-click="reject-all"
                data-confirm="Reject all candidates?"
                class="text-sm text-[var(--color-error)] hover:text-[var(--color-error)]/80 transition-colors cursor-pointer"
              >
                Reject All
              </button>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
              <div
                :for={candidate <- @candidates}
                class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-[var(--shadow-card)] overflow-hidden"
              >
                <div class="aspect-square bg-[var(--color-surface-sunken)] flex items-center justify-center overflow-hidden">
                  <img
                    src={candidate.thumbnail_url}
                    alt="Immich suggestion"
                    class="object-cover w-full h-full"
                    loading="lazy"
                  />
                </div>
                <div class="p-4">
                  <p class="text-sm text-[var(--color-text-tertiary)] mb-3">
                    Suggested <.date_display date={candidate.suggested_at} />
                  </p>
                  <div class="flex gap-2">
                    <button
                      phx-click="accept"
                      phx-value-candidate-id={candidate.id}
                      class="flex-1 inline-flex items-center justify-center rounded-[var(--radius-md)] bg-[var(--color-success)] text-[var(--color-success-foreground)] text-sm py-2 px-3 font-medium hover:bg-[var(--color-success)]/90 transition-colors cursor-pointer"
                    >
                      Accept
                    </button>
                    <button
                      phx-click="reject"
                      phx-value-candidate-id={candidate.id}
                      class="flex-1 inline-flex items-center justify-center rounded-[var(--radius-md)] bg-[var(--color-error-subtle)] text-[var(--color-error)] text-sm py-2 px-3 font-medium hover:bg-[var(--color-error)]/20 transition-colors cursor-pointer"
                    >
                      Reject
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
