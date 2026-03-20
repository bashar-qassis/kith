defmodule KithWeb.KithComponents do
  @moduledoc """
  Custom function components for the Kith application.

  These are Level 3 components built on top of CoreComponents,
  providing domain-specific UI elements like avatars, contact badges,
  tag pills, reminder rows, and date/time displays.
  """

  use Phoenix.Component
  import KithWeb.CoreComponents

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @avatar_colors ~w(
    bg-red-500 bg-orange-500 bg-amber-500 bg-yellow-500 bg-lime-500
    bg-green-500 bg-emerald-500 bg-teal-500 bg-cyan-500 bg-sky-500
    bg-blue-500 bg-indigo-500 bg-violet-500 bg-purple-500 bg-fuchsia-500
    bg-pink-500 bg-rose-500
  )

  defp name_to_color(nil), do: Enum.at(@avatar_colors, 0)
  defp name_to_color(""), do: Enum.at(@avatar_colors, 0)

  defp name_to_color(name) do
    index =
      name
      |> String.to_charlist()
      |> Enum.sum()
      |> rem(length(@avatar_colors))

    Enum.at(@avatar_colors, index)
  end

  defp initials(nil), do: "?"
  defp initials(""), do: "?"

  defp initials(name) do
    parts =
      name
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)

    case parts do
      [] ->
        "?"

      [single] ->
        single |> String.upcase() |> String.slice(0, 2)

      [first | rest] ->
        last = List.last(rest)
        String.at(first, 0) |> String.upcase() |> Kernel.<>(String.at(last, 0) |> String.upcase())
    end
  end

  defp avatar_size_classes(:sm), do: "size-8 text-xs"
  defp avatar_size_classes(:md), do: "size-10 text-sm"
  defp avatar_size_classes(:lg), do: "size-14 text-base"
  defp avatar_size_classes(_), do: avatar_size_classes(:md)

  defp tag_color(nil, name), do: name_to_color(name || "")

  defp tag_color(color, _name) do
    "bg-#{color}-100 text-#{color}-800 dark:bg-#{color}-900 dark:text-#{color}-200"
  end

  defp role_classes("admin"), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
  defp role_classes("editor"), do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"
  defp role_classes("viewer"), do: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"
  defp role_classes(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"

  defp emotion_classes(emotion) when is_binary(emotion) do
    case String.downcase(emotion) do
      "love" -> "bg-pink-100 text-pink-800"
      "happy" -> "bg-yellow-100 text-yellow-800"
      "grateful" -> "bg-green-100 text-green-800"
      "sad" -> "bg-blue-100 text-blue-800"
      "angry" -> "bg-red-100 text-red-800"
      "anxious" -> "bg-orange-100 text-orange-800"
      "neutral" -> "bg-gray-100 text-gray-800"
      _ -> "bg-purple-100 text-purple-800"
    end
  end

  defp reminder_icon_name(%{type: "birthday"}), do: "hero-cake"
  defp reminder_icon_name(%{type: "anniversary"}), do: "hero-heart"
  defp reminder_icon_name(%{type: "call"}), do: "hero-phone"
  defp reminder_icon_name(%{type: "email"}), do: "hero-envelope"
  defp reminder_icon_name(%{type: "meeting"}), do: "hero-calendar-days"
  defp reminder_icon_name(_), do: "hero-bell"

  defp format_reminder_date(%{date: date}, locale) do
    case Kith.Cldr.Date.to_string(date, locale: locale, format: :medium) do
      {:ok, formatted} -> formatted
      _ -> to_string(date)
    end
  end

  defp format_reminder_date(_, _locale), do: ""

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  @doc """
  Renders a contact/user avatar with initials fallback.

  ## Examples

      <.avatar name="John Doe" />
      <.avatar src="/images/avatar.jpg" name="John Doe" size={:lg} />
  """
  attr :id, :string, default: nil
  attr :src, :string, default: nil
  attr :name, :string, default: nil
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :class, :string, default: nil

  def avatar(assigns) do
    assigns =
      assigns
      |> assign(:initials_text, initials(assigns.name))
      |> assign(:bg_color, name_to_color(assigns.name))
      |> assign(:size_classes, avatar_size_classes(assigns.size))

    ~H"""
    <div
      id={@id}
      class={[
        "inline-flex items-center justify-center rounded-full shrink-0 font-semibold text-white select-none",
        @size_classes,
        !@src && @bg_color,
        @class
      ]}
    >
      <img
        :if={@src}
        src={@src}
        alt={@name || "Avatar"}
        class={["rounded-full object-cover", @size_classes]}
      />
      <span :if={!@src}>{@initials_text}</span>
    </div>
    """
  end

  @doc """
  Renders an avatar + name chip that links to a contact profile.

  ## Examples

      <.contact_badge contact={%{id: 1, display_name: "John Doe", avatar_url: nil}} />
  """
  attr :id, :string, default: nil
  attr :contact, :map, required: true
  attr :navigate, :string, default: nil

  def contact_badge(assigns) do
    assigns =
      assign_new(assigns, :href, fn ->
        assigns.navigate || "/contacts/#{assigns.contact.id}"
      end)

    ~H"""
    <.link
      id={@id}
      navigate={@href}
      class="inline-flex items-center gap-2 rounded-full bg-base-200 pe-3 ps-1 py-1 text-sm font-medium hover:bg-base-300 transition-colors"
    >
      <.avatar
        src={Map.get(@contact, :avatar_url)}
        name={Map.get(@contact, :display_name, "")}
        size={:sm}
      />
      <span class="truncate max-w-[12rem]">{Map.get(@contact, :display_name, "")}</span>
    </.link>
    """
  end

  @doc """
  Renders a colored tag pill.

  ## Examples

      <.tag_badge tag={%{name: "Family", color: "blue"}} />
      <.tag_badge tag={%{name: "Work", color: nil}} />
  """
  attr :id, :string, default: nil
  attr :tag, :map, required: true
  attr :class, :string, default: nil

  def tag_badge(assigns) do
    color = Map.get(assigns.tag, :color)
    name = Map.get(assigns.tag, :name, "")

    assigns =
      if color do
        assign(assigns, :color_classes, tag_color(color, name))
      else
        assign(assigns, :color_classes, "#{name_to_color(name)} text-white")
      end

    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
        @color_classes,
        @class
      ]}
    >
      {Map.get(@tag, :name, "")}
    </span>
    """
  end

  @doc """
  Renders a reminder row with type icon and formatted date.

  ## Examples

      <.reminder_row reminder={%{type: "birthday", title: "John's birthday", date: ~D[2026-04-15]}} />
  """
  attr :id, :string, default: nil
  attr :reminder, :map, required: true
  attr :locale, :string, default: "en"

  def reminder_row(assigns) do
    assigns =
      assigns
      |> assign(:icon_name, reminder_icon_name(assigns.reminder))
      |> assign(:formatted_date, format_reminder_date(assigns.reminder, assigns.locale))

    ~H"""
    <div id={@id} class="flex items-center gap-3 py-2">
      <div class="flex items-center justify-center size-8 rounded-full bg-base-200 shrink-0">
        <.icon name={@icon_name} class="size-4" />
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium truncate">{Map.get(@reminder, :title, "")}</p>
        <p class="text-xs text-base-content/60">{@formatted_date}</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a standard card container.

  ## Examples

      <.card>
        <:header>Card Title</:header>
        Some content here.
        <:footer>Footer content</:footer>
      </.card>
  """
  attr :id, :string, default: nil
  attr :class, :string, default: nil

  slot :header
  slot :inner_block, required: true
  slot :footer

  def card(assigns) do
    ~H"""
    <div id={@id} class={["card bg-base-100 shadow-sm border border-base-200", @class]}>
      <div :if={@header != []} class="card-body pb-0">
        <div class="card-title">{render_slot(@header)}</div>
      </div>
      <div class="card-body">
        {render_slot(@inner_block)}
      </div>
      <div :if={@footer != []} class="card-body pt-0 border-t border-base-200">
        {render_slot(@footer)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a section title with optional action button.

  ## Examples

      <.section_header title="Recent Activity">
        <:actions>
          <button class="btn btn-sm">View All</button>
        </:actions>
      </.section_header>
  """
  attr :id, :string, default: nil
  attr :title, :string, required: true

  slot :actions

  def section_header(assigns) do
    ~H"""
    <div id={@id} class="flex items-center justify-between mb-4">
      <h2 class="text-lg font-semibold">{@title}</h2>
      <div :if={@actions != []} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty state with icon, message, and optional CTA.

  ## Examples

      <.empty_state icon="hero-users" title="No contacts" message="Get started by adding your first contact.">
        <:actions>
          <button class="btn btn-primary">Add Contact</button>
        </:actions>
      </.empty_state>
  """
  attr :id, :string, default: nil
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, default: nil

  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col items-center justify-center py-12 text-center">
      <div class="flex items-center justify-center size-16 rounded-full bg-base-200 mb-4">
        <.icon name={@icon} class="size-8 text-base-content/40" />
      </div>
      <h3 class="text-lg font-semibold mb-1">{@title}</h3>
      <p :if={@message} class="text-sm text-base-content/60 max-w-sm mb-4">{@message}</p>
      <div :if={@actions != []} class="flex items-center gap-2 mt-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a role badge chip with color coding.

  ## Examples

      <.role_badge role="admin" />
      <.role_badge role="editor" />
      <.role_badge role="viewer" />
  """
  attr :id, :string, default: nil
  attr :role, :string, required: true

  def role_badge(assigns) do
    assigns = assign(assigns, :role_classes, role_classes(assigns.role))

    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium capitalize",
        @role_classes
      ]}
    >
      {@role}
    </span>
    """
  end

  @doc """
  Renders an emotion label chip.

  ## Examples

      <.emotion_badge emotion="happy" />
      <.emotion_badge emotion="grateful" />
  """
  attr :id, :string, default: nil
  attr :emotion, :string, required: true

  def emotion_badge(assigns) do
    assigns = assign(assigns, :emotion_classes, emotion_classes(assigns.emotion))

    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium capitalize",
        @emotion_classes
      ]}
    >
      {@emotion}
    </span>
    """
  end

  @doc """
  Renders a date using Kith.Cldr for locale-aware formatting.

  ## Examples

      <.date_display date={~D[2026-03-21]} />
      <.date_display date={~D[2026-03-21]} locale="fr" format={:long} />
  """
  attr :id, :string, default: nil
  attr :date, :any, required: true
  attr :locale, :string, default: "en"
  attr :format, :atom, default: :medium

  def date_display(assigns) do
    formatted =
      case Kith.Cldr.Date.to_string(assigns.date, locale: assigns.locale, format: assigns.format) do
        {:ok, str} -> str
        _ -> to_string(assigns.date)
      end

    assigns = assign(assigns, :formatted, formatted)

    ~H"""
    <time id={@id} datetime={to_string(@date)}>{@formatted}</time>
    """
  end

  @doc """
  Renders relative time (e.g. "2 hours ago") using Kith.Cldr.

  ## Examples

      <.relative_time datetime={~U[2026-03-21 10:00:00Z]} />
  """
  attr :id, :string, default: nil
  attr :datetime, :any, required: true
  attr :locale, :string, default: "en"

  def relative_time(assigns) do
    formatted =
      case Kith.Cldr.DateTime.Relative.to_string(assigns.datetime, locale: assigns.locale) do
        {:ok, str} -> str
        _ -> to_string(assigns.datetime)
      end

    assigns = assign(assigns, :formatted, formatted)

    ~H"""
    <time id={@id} datetime={to_string(@datetime)} title={to_string(@datetime)}>{@formatted}</time>
    """
  end
end
