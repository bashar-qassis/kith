defmodule KithWeb.SettingsLive.SettingsLayout do
  @moduledoc """
  Shared settings sidebar navigation component used by all settings pages.
  """

  use KithWeb, :html

  attr :current_path, :string, required: true
  attr :current_scope, :map, required: true
  slot :inner_block, required: true

  def settings_shell(assigns) do
    ~H"""
    <div class="flex flex-col md:flex-row gap-8">
      <%!-- Settings sidebar --%>
      <nav class="w-full md:w-56 shrink-0">
        <ul class="space-y-0.5">
          <.settings_nav_item
            path={~p"/users/settings"}
            current_path={@current_path}
            icon="hero-user"
            label="Profile"
          />
          <%= if authorized?(@current_scope.user, :manage, :account) do %>
            <.settings_nav_item
              path={~p"/settings/account"}
              current_path={@current_path}
              icon="hero-building-office"
              label="Account"
            />
          <% end %>
          <.settings_nav_item
            path={~p"/settings/tags"}
            current_path={@current_path}
            icon="hero-tag"
            label="Tags"
          />
          <.settings_nav_item
            path={~p"/settings/emotions"}
            current_path={@current_path}
            icon="hero-face-smile"
            label="Emotions"
          />
          <.settings_nav_item
            path={~p"/settings/activity-types"}
            current_path={@current_path}
            icon="hero-rectangle-group"
            label="Activity Types"
          />
          <.settings_nav_item
            path={~p"/settings/life-event-types"}
            current_path={@current_path}
            icon="hero-star"
            label="Life Event Types"
          />
          <%= if authorized?(@current_scope.user, :manage, :account) do %>
            <.settings_nav_item
              path={~p"/settings/integrations"}
              current_path={@current_path}
              icon="hero-puzzle-piece"
              label="Integrations"
            />
          <% end %>
          <.settings_nav_item
            path={~p"/settings/import"}
            current_path={@current_path}
            icon="hero-arrow-up-tray"
            label="Import"
          />
          <.settings_nav_item
            path={~p"/settings/imports"}
            current_path={@current_path}
            icon="hero-clock"
            label="Import History"
          />
          <.settings_nav_item
            path={~p"/settings/export"}
            current_path={@current_path}
            icon="hero-arrow-down-tray"
            label="Export"
          />
          <%= if authorized?(@current_scope.user, :manage, :account) do %>
            <.settings_nav_item
              path={~p"/settings/audit-log"}
              current_path={@current_path}
              icon="hero-clipboard-document-list"
              label="Audit Log"
            />
          <% end %>
        </ul>
      </nav>

      <%!-- Settings content --%>
      <div class="flex-1 min-w-0">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp settings_nav_item(assigns) do
    active = assigns.current_path == assigns.path
    assigns = assign(assigns, :active, active)

    ~H"""
    <li>
      <.link
        navigate={@path}
        aria-current={@active && "page"}
        class={[
          "flex items-center gap-3 rounded-[var(--radius-md)] px-3 py-2 text-sm font-medium transition-colors duration-150",
          @active &&
            "bg-[var(--color-surface-elevated)] text-[var(--color-accent)] border-s-2 border-[var(--color-accent)]",
          !@active &&
            "text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-elevated)] hover:text-[var(--color-text-primary)]"
        ]}
      >
        <.icon name={@icon} class="size-5 shrink-0" />
        {@label}
      </.link>
    </li>
    """
  end
end
