defmodule KithWeb.ContactLive.ConversationsComponent do
  use KithWeb, :live_component

  alias Kith.Conversations
  alias Kith.Conversations.Conversation

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:conversations, [])
     |> assign(:show_form, false)
     |> assign(:expanded_conversation_id, nil)
     |> assign(:show_message_form, false)}
  end

  @impl true
  def update(assigns, socket) do
    conversations = Conversations.list_conversations(assigns.account_id, assigns.contact_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:conversations, conversations)
     |> assign_new(:changeset, fn -> Conversation.changeset(%Conversation{}, %{}) end)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:changeset, Conversation.changeset(%Conversation{}, %{}))}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("save-conversation", %{"conversation" => conv_params}, socket) do
    params = Map.put(conv_params, "contact_id", socket.assigns.contact_id)

    case Conversations.create_conversation(
           socket.assigns.account_id,
           socket.assigns.current_user_id,
           params
         ) do
      {:ok, conversation} ->
        conversations =
          Conversations.list_conversations(socket.assigns.account_id, socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:conversations, conversations)
         |> assign(:show_form, false)
         |> assign(:expanded_conversation_id, conversation.id)
         |> assign(:show_message_form, true)
         |> put_flash(:info, "Conversation created.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("expand-conversation", %{"id" => id}, socket) do
    conv_id = String.to_integer(id)

    {expanded_id, show_msg_form} =
      if socket.assigns.expanded_conversation_id == conv_id do
        {nil, false}
      else
        {conv_id, false}
      end

    {:noreply,
     socket
     |> assign(:expanded_conversation_id, expanded_id)
     |> assign(:show_message_form, show_msg_form)}
  end

  def handle_event("show-message-form", _params, socket) do
    {:noreply, assign(socket, :show_message_form, true)}
  end

  def handle_event("cancel-message-form", _params, socket) do
    {:noreply, assign(socket, :show_message_form, false)}
  end

  def handle_event("add-message", %{"message" => msg_params}, socket) do
    conversation =
      Conversations.get_conversation!(
        socket.assigns.account_id,
        socket.assigns.expanded_conversation_id
      )

    params =
      Map.put_new(
        msg_params,
        "sent_at",
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )

    case Conversations.add_message(conversation, params) do
      {:ok, _message} ->
        conversations =
          Conversations.list_conversations(socket.assigns.account_id, socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:conversations, conversations)
         |> assign(:show_message_form, false)
         |> put_flash(:info, "Message added.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(:error, "Could not add message.")}
    end
  end

  def handle_event("delete-conversation", %{"id" => id}, socket) do
    conversation =
      Conversations.get_conversation!(
        socket.assigns.account_id,
        String.to_integer(id)
      )

    {:ok, _} = Conversations.delete_conversation(conversation)

    conversations =
      Conversations.list_conversations(socket.assigns.account_id, socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:conversations, conversations)
     |> assign(:expanded_conversation_id, nil)
     |> assign(:show_message_form, false)
     |> put_flash(:info, "Conversation deleted.")}
  end

  defp platform_label("sms"), do: "SMS"
  defp platform_label("whatsapp"), do: "WhatsApp"
  defp platform_label("telegram"), do: "Telegram"
  defp platform_label("email"), do: "Email"
  defp platform_label("instagram"), do: "Instagram"
  defp platform_label("messenger"), do: "Messenger"
  defp platform_label("signal"), do: "Signal"
  defp platform_label("other"), do: "Other"
  defp platform_label(val), do: String.capitalize(val || "Other")

  defp platform_icon("sms"), do: "hero-chat-bubble-left"
  defp platform_icon("whatsapp"), do: "hero-chat-bubble-left-right"
  defp platform_icon("telegram"), do: "hero-paper-airplane"
  defp platform_icon("email"), do: "hero-envelope"
  defp platform_icon("instagram"), do: "hero-camera"
  defp platform_icon("messenger"), do: "hero-chat-bubble-oval-left-ellipsis"
  defp platform_icon("signal"), do: "hero-shield-check"
  defp platform_icon(_), do: "hero-chat-bubble-left-right"

  defp platform_badge_class("sms"),
    do: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"

  defp platform_badge_class("whatsapp"),
    do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400"

  defp platform_badge_class("telegram"),
    do: "bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-400"

  defp platform_badge_class("email"),
    do: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"

  defp platform_badge_class("instagram"),
    do: "bg-pink-100 text-pink-700 dark:bg-pink-900/30 dark:text-pink-400"

  defp platform_badge_class("messenger"),
    do: "bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400"

  defp platform_badge_class("signal"),
    do: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"

  defp platform_badge_class(_),
    do: "bg-gray-100 text-gray-700 dark:bg-gray-900/30 dark:text-gray-400"

  defp message_count(conversation) do
    case conversation.messages do
      nil -> 0
      messages -> length(messages)
    end
  end

  defp last_message(conversation) do
    case conversation.messages do
      nil -> nil
      [] -> nil
      messages -> List.last(Enum.sort_by(messages, & &1.sent_at, DateTime))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Conversations</h2>
        <%= if @can_edit do %>
          <button
            id={"add-conversation-#{@contact_id}"}
            phx-click="show-form"
            phx-target={@myself}
            class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
          >
            <.icon name="hero-plus" class="size-4" /> New Conversation
          </button>
        <% end %>
      </div>

      <%!-- New conversation form --%>
      <%= if @show_form do %>
        <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-sm mb-4">
          <div class="p-4">
            <.form for={%{}} phx-submit="save-conversation" phx-target={@myself}>
              <div class="space-y-3">
                <div>
                  <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                    Subject
                  </label>
                  <input
                    type="text"
                    name="conversation[subject]"
                    placeholder="What was the conversation about?"
                    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                    Platform
                  </label>
                  <select
                    name="conversation[platform]"
                    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                  >
                    <option value="sms">SMS</option>
                    <option value="whatsapp">WhatsApp</option>
                    <option value="telegram">Telegram</option>
                    <option value="email">Email</option>
                    <option value="instagram">Instagram</option>
                    <option value="messenger">Messenger</option>
                    <option value="signal">Signal</option>
                    <option value="other" selected>Other</option>
                  </select>
                </div>
              </div>
              <div class="flex gap-2 mt-3">
                <button
                  type="submit"
                  class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
                >
                  Create
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

      <%!-- Conversations list --%>
      <%= if @conversations == [] and not @show_form do %>
        <KithUI.empty_state
          size={:compact}
          icon="hero-chat-bubble-left-right"
          title="No conversations yet"
          message="Log conversations you've had with this contact."
        >
          <:actions :if={@can_edit}>
            <button
              phx-click="show-form"
              phx-target={@myself}
              class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
            >
              New Conversation
            </button>
          </:actions>
        </KithUI.empty_state>
      <% end %>

      <div class="space-y-3">
        <%= for conversation <- @conversations do %>
          <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-sm">
            <%!-- Conversation header (clickable to expand) --%>
            <button
              phx-click="expand-conversation"
              phx-value-id={conversation.id}
              phx-target={@myself}
              class="w-full text-left p-4 cursor-pointer hover:bg-[var(--color-surface-sunken)]/50 transition-colors rounded-[var(--radius-lg)]"
            >
              <div class="flex items-start justify-between">
                <div class="flex items-start gap-3 flex-1">
                  <div class="mt-0.5 flex-shrink-0">
                    <.icon
                      name={platform_icon(conversation.platform)}
                      class="size-5 text-[var(--color-accent)]"
                    />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 flex-wrap">
                      <p class="text-sm font-medium text-[var(--color-text-primary)]">
                        {conversation.subject || "Untitled Conversation"}
                      </p>
                      <span class={[
                        "inline-flex items-center rounded-full px-1.5 py-0.5 text-[10px] font-medium",
                        platform_badge_class(conversation.platform)
                      ]}>
                        {platform_label(conversation.platform)}
                      </span>
                    </div>
                    <div class="flex items-center gap-2 mt-1">
                      <span class="text-xs text-[var(--color-text-tertiary)]">
                        {message_count(conversation)} {if message_count(conversation) == 1,
                          do: "message",
                          else: "messages"}
                      </span>
                      <%= if last_msg = last_message(conversation) do %>
                        <span class="text-xs text-[var(--color-text-tertiary)]">&middot;</span>
                        <span class="text-xs text-[var(--color-text-tertiary)] truncate max-w-[200px]">
                          {String.slice(last_msg.body || "", 0..60)}
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>
                <div class="flex items-center gap-2 ms-2 shrink-0">
                  <span class="text-xs text-[var(--color-text-tertiary)]">
                    <.date_display date={conversation.updated_at} />
                  </span>
                  <.icon
                    name={
                      if @expanded_conversation_id == conversation.id,
                        do: "hero-chevron-up",
                        else: "hero-chevron-down"
                    }
                    class="size-4 text-[var(--color-text-tertiary)]"
                  />
                </div>
              </div>
            </button>

            <%!-- Expanded conversation: messages --%>
            <%= if @expanded_conversation_id == conversation.id do %>
              <div class="border-t border-[var(--color-border)] px-4 pb-4">
                <%!-- Messages list --%>
                <%= if conversation.messages == [] do %>
                  <p class="text-sm text-[var(--color-text-tertiary)] py-4 text-center">
                    No messages yet. Add the first one below.
                  </p>
                <% else %>
                  <div class="space-y-3 py-3">
                    <%= for message <- Enum.sort_by(conversation.messages, & &1.sent_at, DateTime) do %>
                      <div class={[
                        "flex",
                        message.direction == "sent" && "justify-end",
                        message.direction == "received" && "justify-start"
                      ]}>
                        <div class={[
                          "max-w-[80%] rounded-[var(--radius-lg)] px-3 py-2",
                          message.direction == "sent" &&
                            "bg-[var(--color-accent)] text-[var(--color-accent-foreground)]",
                          message.direction == "received" &&
                            "bg-[var(--color-surface-sunken)] text-[var(--color-text-primary)]"
                        ]}>
                          <p class="text-sm whitespace-pre-wrap">{message.body}</p>
                          <p class={[
                            "text-[10px] mt-1",
                            message.direction == "sent" && "text-[var(--color-accent-foreground)]/70",
                            message.direction == "received" && "text-[var(--color-text-tertiary)]"
                          ]}>
                            <.datetime_display datetime={message.sent_at} />
                          </p>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%!-- Add message form --%>
                <%= if @can_edit do %>
                  <%= if @show_message_form do %>
                    <div class="mt-3 rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] p-3">
                      <.form for={%{}} phx-submit="add-message" phx-target={@myself}>
                        <div class="space-y-3">
                          <div>
                            <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                              Message *
                            </label>
                            <textarea
                              name="message[body]"
                              rows="3"
                              required
                              placeholder="What was said?"
                              class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                            ></textarea>
                          </div>
                          <div class="grid grid-cols-2 gap-3">
                            <div>
                              <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                                Direction *
                              </label>
                              <select
                                name="message[direction]"
                                required
                                class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                              >
                                <option value="sent">Sent</option>
                                <option value="received">Received</option>
                              </select>
                            </div>
                            <div>
                              <label class="block text-sm font-medium text-[var(--color-text-primary)] mb-1">
                                Date/Time
                              </label>
                              <input
                                type="datetime-local"
                                name="message[sent_at]"
                                class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20"
                              />
                            </div>
                          </div>
                        </div>
                        <div class="flex gap-2 mt-3">
                          <button
                            type="submit"
                            class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
                          >
                            Send
                          </button>
                          <button
                            type="button"
                            phx-click="cancel-message-form"
                            phx-target={@myself}
                            class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-sunken)] hover:text-[var(--color-text-primary)] transition-colors cursor-pointer"
                          >
                            Cancel
                          </button>
                        </div>
                      </.form>
                    </div>
                  <% else %>
                    <div class="mt-3 flex items-center gap-2">
                      <button
                        phx-click="show-message-form"
                        phx-target={@myself}
                        class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer"
                      >
                        <.icon name="hero-plus" class="size-4" /> Add Message
                      </button>
                      <button
                        phx-click="delete-conversation"
                        phx-value-id={conversation.id}
                        phx-target={@myself}
                        data-confirm="Delete this conversation and all its messages? This cannot be undone."
                        class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-error)] hover:bg-[var(--color-surface-sunken)] transition-colors cursor-pointer"
                      >
                        <.icon name="hero-trash" class="size-4" /> Delete
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
