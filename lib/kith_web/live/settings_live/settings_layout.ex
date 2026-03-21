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
    <div class="flex flex-col md:flex-row gap-6">
      <%!-- Settings sidebar --%>
      <nav class="w-full md:w-56 shrink-0">
        <ul class="space-y-1">
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
        class={[
          "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
          @active && "bg-primary/10 text-primary",
          !@active && "text-base-content/70 hover:bg-base-300 hover:text-base-content"
        ]}
      >
        <.icon name={@icon} class="size-5 shrink-0" />
        {@label}
      </.link>
    </li>
    """
  end
end
