defmodule KithWeb.Layouts do
  @moduledoc """
  Layout components for the Kith application.

  - `root.html.heex` — HTML skeleton (embedded via embed_templates)
  - `app/1` — Authenticated app shell with sidebar navigation
  """
  use KithWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the authenticated app shell with sidebar navigation.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
        <h1>Content</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      class="flex h-screen bg-base-100"
      x-data="sidebar"
    >
      <%!-- Desktop sidebar --%>
      <aside
        class="hidden md:flex flex-col border-e border-base-300 bg-base-200 transition-all duration-200"
        x-bind:class="sidebarOpen ? 'w-64' : 'w-16'"
      >
        <%!-- Logo & collapse toggle --%>
        <div class="flex items-center justify-between p-4 border-b border-base-300">
          <a href="/" class="font-bold text-lg" x-show="sidebarOpen" x-transition>Kith</a>
          <button
            x-on:click="toggle()"
            class="btn btn-ghost btn-sm btn-square"
            aria-label="Toggle sidebar"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
        </div>

        <%!-- Navigation links --%>
        <nav class="flex-1 py-4 space-y-1 px-2">
          <.sidebar_link
            path={~p"/dashboard"}
            current_path={@current_path}
            icon="hero-home"
            label="Dashboard"
          />
          <.sidebar_link
            path={~p"/contacts"}
            current_path={@current_path}
            icon="hero-user-group"
            label="Contacts"
            match_prefix="/contacts"
          />
          <.sidebar_link
            path={~p"/reminders/upcoming"}
            current_path={@current_path}
            icon="hero-bell"
            label="Reminders"
            match_prefix="/reminders"
          />
          <.sidebar_link
            path={~p"/users/settings"}
            current_path={@current_path}
            icon="hero-cog-6-tooth"
            label="Settings"
            match_prefix="/settings"
          />
        </nav>

        <%!-- User footer --%>
        <%= if @current_scope && @current_scope.user do %>
          <div class="border-t border-base-300 p-3" x-data="userMenu">
            <button
              class="flex items-center gap-2 w-full rounded-lg p-2 hover:bg-base-300 transition-colors"
              x-on:click="toggle"
            >
              <div class="w-8 h-8 rounded-full bg-primary text-primary-content flex items-center justify-center text-sm font-medium shrink-0">
                {user_initials(@current_scope.user)}
              </div>
              <span class="text-sm truncate" x-show="sidebarOpen" x-transition>
                {@current_scope.user.email}
              </span>
            </button>
            <div
              x-show="userMenu"
              x-on:click.outside="close"
              x-transition
              class="mt-1 py-1 rounded-lg bg-base-100 border border-base-300 shadow-lg"
            >
              <.link
                navigate={~p"/users/settings"}
                class="block px-4 py-2 text-sm hover:bg-base-200"
              >
                Settings
              </.link>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="block px-4 py-2 text-sm text-error hover:bg-base-200"
              >
                Log out
              </.link>
            </div>
          </div>
        <% end %>
      </aside>

      <%!-- Main content --%>
      <div class="flex-1 flex flex-col overflow-hidden">
        <%!-- Mobile top bar --%>
        <header class="md:hidden flex items-center justify-between p-4 border-b border-base-300 bg-base-200">
          <a href="/" class="font-bold text-lg">Kith</a>
          <%= if @current_scope && @current_scope.user do %>
            <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
              Log out
            </.link>
          <% end %>
        </header>

        <%!-- Page content --%>
        <main class="flex-1 overflow-y-auto">
          <div class="max-w-6xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
            <.flash_group flash={@flash} />
            {render_slot(@inner_block)}
          </div>
        </main>

        <%!-- Mobile bottom nav --%>
        <nav class="md:hidden flex items-center justify-around border-t border-base-300 bg-base-200 py-2">
          <.mobile_nav_link
            path={~p"/dashboard"}
            current_path={@current_path}
            icon="hero-home"
            label="Home"
          />
          <.mobile_nav_link
            path={~p"/contacts"}
            current_path={@current_path}
            icon="hero-user-group"
            label="Contacts"
            match_prefix="/contacts"
          />
          <.mobile_nav_link
            path={~p"/reminders/upcoming"}
            current_path={@current_path}
            icon="hero-bell"
            label="Reminders"
            match_prefix="/reminders"
          />
          <.mobile_nav_link
            path={~p"/users/settings"}
            current_path={@current_path}
            icon="hero-cog-6-tooth"
            label="Settings"
            match_prefix="/settings"
          />
        </nav>
      </div>
    </div>
    """
  end

  # -- Sidebar link component --

  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :match_prefix, :string, default: nil
  attr :badge_count, :integer, default: 0

  defp sidebar_link(assigns) do
    active = active?(assigns.current_path, assigns.path, assigns.match_prefix)
    assigns = assign(assigns, :active, active)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        @active && "bg-primary/10 text-primary",
        !@active && "text-base-content/70 hover:bg-base-300 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-5 shrink-0" />
      <span x-show="sidebarOpen" x-transition>{@label}</span>
      <%= if @badge_count > 0 do %>
        <span
          x-show="sidebarOpen"
          class="ms-auto bg-warning text-warning-content text-xs font-bold px-2 py-0.5 rounded-full"
        >
          {@badge_count}
        </span>
      <% end %>
    </.link>
    """
  end

  # -- Mobile nav link component --

  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :match_prefix, :string, default: nil

  defp mobile_nav_link(assigns) do
    active = active?(assigns.current_path, assigns.path, assigns.match_prefix)
    assigns = assign(assigns, :active, active)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "flex flex-col items-center gap-1 px-3 py-1 text-xs",
        @active && "text-primary",
        !@active && "text-base-content/60"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <span>{@label}</span>
    </.link>
    """
  end

  # -- Flash group --

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ms-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ms-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  # -- Helpers --

  defp active?(current_path, exact_path, nil), do: current_path == exact_path

  defp active?(current_path, _exact_path, prefix),
    do: String.starts_with?(current_path, prefix)

  defp user_initials(%{email: email}) do
    email
    |> String.first()
    |> String.upcase()
  end
end
