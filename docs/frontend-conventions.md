# Kith Frontend Conventions

**Status:** Active — PR Gate
**Last Updated:** 2026-03-21
**Applies To:** All LiveView screens, LiveComponents, and function components

> No LiveView screen may be merged without this document existing and the implementation conforming to it.

---

## Table of Contents

1. [Component Hierarchy (3 Levels)](#1-component-hierarchy-3-levels)
2. [Alpine.js Scope Boundary](#2-alpinejs-scope-boundary)
3. [RTL-Safe Tailwind Conventions](#3-rtl-safe-tailwind-conventions)
4. [Kith.Policy.can?/3 Interface](#4-kithpolicycan3-interface)
5. [Auth Convention Gate](#5-auth-convention-gate)
6. [Design System — "Warm Precision"](#6-design-system--warm-precision)
7. [Animation Conventions](#7-animation-conventions)
8. [Component Variant Patterns](#8-component-variant-patterns)

---

## 1. Component Hierarchy (3 Levels)

### Level 1: LiveView Modules

One module per route. Owns all socket state for that screen. Contains no rendering logic — delegates entirely to Level 2 components and Level 3 function components.

**Responsibilities:**
- `mount/3`: authenticate, authorize via `Kith.Policy.can?/3`, load initial data, assign to socket
- `handle_params/3`: handle URL params, pagination cursors, filter state
- `handle_event/3`: top-level events not owned by a child component
- `render/1`: a single `~H"""` block delegating to components — no business logic inline

**Examples:** `ContactListLive`, `ContactShowLive`, `DashboardLive`, `SettingsLive`, `TimelineLive`, `ImportLive`

```elixir
# CORRECT — LiveView module delegates rendering
defmodule KithWeb.ContactShowLive do
  use KithWeb, :live_view

  def mount(%{"id" => id}, _session, socket) do
    unless Kith.Policy.can?(socket.assigns.current_user, :read, :contact) do
      {:ok, push_navigate(socket, to: ~p"/403")}
    else
      contact = Contacts.get_contact!(id)
      {:ok, assign(socket, contact: contact)}
    end
  end

  def render(assigns) do
    ~H"""
    <.contact_header contact={@contact} current_user={@current_user} />
    <.live_component module={KithWeb.NotesListComponent} id="notes" contact={@contact} />
    <.live_component module={KithWeb.ActivitiesListComponent} id="activities" contact={@contact} />
    """
  end
end
```

---

### Level 2: LiveComponents

Stateful sub-units with independent data loading. Own their events. Communicate up to the parent LiveView via `send/2` or `Phoenix.PubSub` — never by directly mutating parent socket assigns.

**Responsibilities:**
- `update/2`: load or refresh their own data slice
- `handle_event/3`: handle events scoped to this component
- May contain their own `assign_async/3` calls for non-blocking data loads
- Must not reach across component boundaries to read sibling state

**Examples:**
- `NotesListComponent` — paginated note list + inline create form
- `ActivitiesListComponent` — activity log with filter
- `PhotoGalleryComponent` — photo grid with lightbox trigger
- `ImmichReviewComponent` — Immich suggestion review UI (read-only Immich, confirm to link)
- `ContactFormComponent` — multi-section contact edit form

```elixir
# CORRECT — LiveComponent owns its data and events
defmodule KithWeb.NotesListComponent do
  use KithWeb, :live_component

  def update(%{contact: contact} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_async(:notes, fn -> {:ok, %{notes: Notes.list_for_contact(contact.id)}} end)}
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    # authorized action, then notify parent
    :ok = Notes.delete_note(id)
    send(self(), {:note_deleted, id})
    {:noreply, socket}
  end
end
```

---

### Level 3: Function Components

Stateless, pure render. No Phoenix module required — defined as functions in `KithWeb.CoreComponents` or in domain-specific component modules (e.g., `KithWeb.ContactComponents`, `KithWeb.FormComponents`).

**Rules:**
- Accept only `assigns` — no side effects, no data fetching
- Must be fully idempotent given the same assigns
- Visibility gating via `Kith.Policy.can?/3` is done here for UI chrome controls

**Canonical set (non-exhaustive):**

| Component | Location | Purpose |
|---|---|---|
| `.contact_badge` | `ContactComponents` | Inline contact chip with avatar |
| `.tag_badge` | `CoreComponents` | Colored tag pill |
| `.form_field` | `FormComponents` | Labeled input wrapper with error |
| `.card` | `CoreComponents` | Surface container with optional header |
| `.reminder_row` | `ContactComponents` | Single reminder line item |
| `.empty_state` | `CoreComponents` | Zero-data placeholder with CTA |
| `.avatar` | `CoreComponents` | Initials or photo avatar |
| `.date_display` | `CoreComponents` | Locale-aware formatted date |
| `.relative_time` | `CoreComponents` | "3 days ago" relative timestamp |

```heex
<%!-- CORRECT — function component, pure render --%>
<.contact_badge contact={@contact} />

<%!-- CORRECT — policy gate at render time --%>
<%= if Kith.Policy.can?(@current_user, :delete, :contact) do %>
  <.button phx-click="delete" phx-value-id={@contact.id} variant="danger">Delete</.button>
<% end %>
```

---

## 2. Alpine.js Scope Boundary

Alpine.js handles **UI chrome only** — local toggle state that has no server-side meaning. It must never be used as a substitute for LiveView state management.

### Alpine IS Responsible For

| Use Case | Example |
|---|---|
| Dropdown menus | `x-data="{ open: false }"` on a menu wrapper |
| Tooltips | `x-show="tooltip"` on hover |
| Clipboard copy | `x-on:click="navigator.clipboard.writeText($el.dataset.value)"` |
| Keyboard shortcuts | `x-on:keydown.escape.window="open = false"` |
| Sidebar collapse | `x-data="{ collapsed: false }"` persisted to `localStorage` |
| Local toggle state | Accordion expand, tab selection, modal open/close |
| Character counters | `x-text="$refs.input.value.length + '/500'"` |
| Lightbox gallery | CSS class toggling, current index tracking |

### Alpine is NOT Responsible For

- Reading or writing server state
- Submitting forms or mutating contact fields
- Making API or fetch calls
- Managing paginated lists, search results, or any data that lives in the database

**All data changes go through LiveView forms (`phx-submit`) or explicit `phx-click` / `phx-change` events.**

### Correct and Incorrect Examples

```html
<!-- CORRECT: dropdown toggle — pure UI state -->
<div x-data="{ open: false }">
  <button x-on:click="open = !open">Options</button>
  <ul x-show="open" x-on:click.outside="open = false">...</ul>
</div>

<!-- CORRECT: clipboard copy — no server state -->
<button
  data-value={@contact.email}
  x-on:click="navigator.clipboard.writeText($el.dataset.value)"
>
  Copy email
</button>

<!-- CORRECT: character counter — local input feedback -->
<div x-data>
  <textarea x-ref="note" phx-change="update_note" maxlength="500"></textarea>
  <span x-text="$refs.note.value.length + '/500'"></span>
</div>

<!-- INCORRECT: API call from Alpine — use phx-click instead -->
<button x-on:click="fetch('/api/contacts/1/favorite', { method: 'POST' })">
  Favorite
</button>
<!-- FIX: <button phx-click="toggle_favorite" phx-value-id={@contact.id}>Favorite</button> -->

<!-- INCORRECT: managing server state in Alpine -->
<div x-data="{ contacts: [] }" x-init="fetch('/api/contacts').then(r => r.json()).then(d => contacts = d)">
  ...
</div>
<!-- FIX: Load contacts in LiveView mount/3, pass to template as @contacts -->
```

### Alpine ↔ LiveView Handoff Pattern

When an Alpine-controlled UI element needs to trigger a server action, use a hidden input or a `phx-click` on the element directly. Alpine may toggle the visible state optimistically while LiveView confirms:

```html
<!-- Tab UI: Alpine controls visual selection, phx-click notifies server -->
<div x-data="{ tab: 'notes' }">
  <button
    x-on:click="tab = 'notes'"
    phx-click="switch_tab"
    phx-value-tab="notes"
    :class="{ 'border-b-2 border-primary-600': tab === 'notes' }"
  >
    Notes
  </button>
</div>
```

---

## 3. RTL-Safe Tailwind Conventions

Kith targets multilingual users including Arabic and Hebrew. All spacing and positioning must use **CSS logical properties** so layouts mirror correctly under `dir="rtl"`.

### Root Layout

The root layout template must set `dir` and `lang` based on the current locale:

```heex
<html dir={html_dir(@locale)} lang={@locale}>
```

`html_dir/1` is a helper in `KithWeb.Helpers` that returns `"rtl"` for RTL locales and `"ltr"` otherwise.

### Property Mapping Reference

| Physical (LTR-only) | Logical (RTL-safe) | Notes |
|---|---|---|
| `ml-*` | `ms-*` | margin-inline-start |
| `mr-*` | `me-*` | margin-inline-end |
| `pl-*` | `ps-*` | padding-inline-start |
| `pr-*` | `pe-*` | padding-inline-end |
| `left-*` | `start-*` | inset-inline-start (positioning) |
| `right-*` | `end-*` | inset-inline-end (positioning) |
| `text-left` | `text-start` | inline-start alignment |
| `text-right` | `text-end` | inline-end alignment |
| `border-l-*` | `border-s-*` | border-inline-start |
| `border-r-*` | `border-e-*` | border-inline-end |
| `rounded-l-*` | `rounded-s-*` | border-radius inline-start |
| `rounded-r-*` | `rounded-e-*` | border-radius inline-end |
| `float-left` | `float-start` | float inline-start |
| `float-right` | `float-end` | float inline-end |

**Physical `top-*` and `bottom-*` are acceptable** — these are block-axis and do not flip with RTL.

### Rules

1. **Never use** `ml-`, `mr-`, `pl-`, `pr-`, `left-`, `right-`, `text-left`, `text-right`, `border-l-`, `border-r-`, `rounded-l-`, `rounded-r-` in component templates. Lint CI will flag these.
2. Physical properties are permitted only in: SVG coordinates, canvas rendering, absolutely positioned overlays where the direction is intentionally fixed (e.g., a global notification stack pinned to the physical right edge).
3. Every major screen must be visually verified in at least one RTL locale (Arabic, `ar`) during development before the PR is merged. Add a note in the PR description: `RTL verified: ar`.
4. Use `space-x-*` carefully — it injects `ml-` internally. Prefer `gap-*` on flex/grid containers.

```html
<!-- INCORRECT -->
<div class="ml-4 pl-3 text-left border-l-2 border-gray-200">...</div>

<!-- CORRECT -->
<div class="ms-4 ps-3 text-start border-s-2 border-gray-200">...</div>
```

---

## 4. Kith.Policy.can?/3 Interface

### Signature

```elixir
Kith.Policy.can?(user :: %Kith.Accounts.User{}, action :: atom(), resource :: atom()) :: boolean()
```

### Where It Is Used

| Location | Purpose |
|---|---|
| `LiveView mount/3` | Redirect unauthorized users before any data loads |
| Function component templates | Hide controls the current user cannot perform |
| Context function guards | Reject unauthorized operations at the domain boundary |

### Visibility Rule

**Viewer-restricted controls are HIDDEN — not disabled or grayed out.**

Do not use `disabled` or reduced opacity to indicate permission absence. If a user cannot perform an action, the control does not render. This prevents confusion and reduces attack surface.

```heex
<%!-- CORRECT: hidden for unauthorized users --%>
<%= if Kith.Policy.can?(@current_user, :create, :note) do %>
  <.button phx-click="new_note">Add Note</.button>
<% end %>

<%!-- INCORRECT: grayed-out control --%>
<.button disabled={!Kith.Policy.can?(@current_user, :create, :note)} class="opacity-50">
  Add Note
</.button>
```

### 403 Page Convention

403 pages must:
- Explain the role limitation in plain language (e.g., "This action requires Editor or Admin access.")
- Link to the account admin or settings page where roles can be managed
- Not expose which specific resource or ID was requested

### Action Atoms

```elixir
:create
:read
:update
:delete
:archive
:restore
:merge
:import
:export
:manage_users
:manage_settings
:manage_account
:trigger_sync
```

### Resource Atoms

```elixir
:contact
:note
:activity
:call
:reminder
:tag
:relationship
:address
:contact_field
:life_event
:photo
:document
:settings
:users
:account
:immich
:audit_log
```

### Role Matrix

| Action | admin | editor | viewer |
|---|---|---|---|
| `:read` (all resources) | yes | yes | yes |
| `:create` | yes | yes | no |
| `:update` | yes | yes | own settings only |
| `:delete` | yes | yes | no |
| `:archive` | yes | yes | no |
| `:restore` | yes | yes | no |
| `:merge` | yes | yes | no |
| `:import` | yes | yes | no |
| `:export` | yes | yes | no |
| `:manage_users` | yes | no | no |
| `:manage_settings` | yes | no | no |
| `:manage_account` | yes | no | no |
| `:trigger_sync` | yes | yes | no |

**Editor note:** editor has full CRUD and import/export but cannot manage users, account settings, or account-level configuration.

**Viewer note:** viewer may call `can?(user, :update, :settings)` only for their own user settings record. All other update/write actions return `false`.

### Usage Pattern in mount/3

```elixir
def mount(_params, _session, socket) do
  user = socket.assigns.current_user

  unless Kith.Policy.can?(user, :read, :contact) do
    {:ok,
     socket
     |> put_flash(:error, "You do not have permission to view contacts.")
     |> push_navigate(to: ~p"/403")}
  else
    {:ok, assign(socket, contacts: Contacts.list_contacts())}
  end
end
```

---

## 5. Auth Convention Gate

When authentication screens are built in **Phase 02/11**, the `Kith.Policy.can?/3` implementation must conform exactly to the atoms defined in Section 4 of this document.

Phase 02 is considered complete only when:

1. `Kith.Policy.can?/3` is implemented and returns correct results for all action/resource combinations in the role matrix above.
2. The three role types (`admin`, `editor`, `viewer`) are assignable to users via the admin UI.
3. All LiveView `mount/3` functions that load protected resources call `Kith.Policy.can?/3` before loading data.
4. The 403 page is implemented per the convention in Section 4.
5. A test module `Kith.PolicyTest` covers every cell in the role matrix.

This document is the **interface contract** for Phase 02. Changes to action atoms, resource atoms, or the role matrix must be proposed as a PR against this document before being implemented in code.

---

---

## 6. Design System — "Warm Precision"

Kith uses a custom design system called **"Warm Precision"** — inspired by Linear's precision, Notion's personality, and Stripe's refinement, but with a distinctive warmth appropriate for a Personal Relationship Manager.

### Design Tone

Like opening a beautifully bound personal notebook. Warm, refined, intentional.

### Color System

All colors use the **OKLCH** color space for perceptual uniformity. Tokens are defined in `assets/css/app.css` via Tailwind v4 `@theme` blocks.

| Token Category | Light Mode | Dark Mode |
|---|---|---|
| `--color-surface` | Stone-50 cream | Stone-950 deep |
| `--color-surface-elevated` | White | Stone-900 |
| `--color-surface-sunken` | Warm stone-100ish | Darker than 950 |
| `--color-surface-overlay` | White | Stone-850ish |
| `--color-text-primary` | Stone-900 | Stone-50 |
| `--color-text-secondary` | Stone-600 | Stone-400 |
| `--color-text-tertiary` | Stone-500 | Stone-500 |
| `--color-border` | Stone-200 | Stone-800 |
| `--color-border-subtle` | Stone-100 | Stone-900 |
| `--color-border-focus` | Amber-500 | Amber-500 |
| `--color-accent` | Amber-600 | Amber-500 |
| `--color-accent-hover` | Amber-700 | Amber-600 |

**Key principle:** Most SaaS apps use cold zinc/slate. Kith's stone + amber palette feels personal, human, and premium — matching its purpose as a *relationship* manager.

### Typography

| Element | Font | Weight | Extra |
|---|---|---|---|
| Body text | Plus Jakarta Sans Variable | 400 (regular) | `leading-relaxed` |
| Labels / emphasis | Plus Jakarta Sans Variable | 500 (medium) | — |
| Headings | Plus Jakarta Sans Variable | 600 (semibold) | `leading-snug`, `tracking-tight` on >= `text-2xl` |
| Code / mono | Geist Mono | 400 | — |

**Never use weight 700 (bold).** Maximum is 600 (semibold) for headings.

Fonts are self-hosted in `priv/static/fonts/` and loaded via `@font-face` with `font-display: swap`.

### Spacing

8px grid system. Use Tailwind's default scale (which is 4px-based: `p-2` = 8px, `p-4` = 16px, etc.). Generous whitespace throughout.

### Border Radius

| Use Case | Token | Value |
|---|---|---|
| Small elements (badges, checkboxes) | `--radius-sm` | 4px |
| Inputs, small cards | `--radius-md` | 6px |
| Cards, panels | `--radius-lg` | 8px |
| Pills, badges | `--radius-full` | 9999px |

### Shadows

Warm-tinted, low opacity. Three levels defined in `@theme`:
- `--shadow-card` — Subtle elevation for cards
- `--shadow-dropdown` — Medium elevation for menus/dropdowns
- `--shadow-modal` — Strong elevation for modals/overlays

### Dark Mode

Uses `[data-theme=dark]` selector (existing mechanism). Dark mode uses deep warm tones (stone-900/950 surfaces) with the amber accent preserved. Override tokens are defined in `:root[data-theme="dark"]` block in `app.css`.

### Component Modules

| Module | Location | Purpose |
|---|---|---|
| `KithWeb.UI` | `lib/kith_web/components/ui.ex` | Core primitives (button, input, modal, table, etc.) |
| `KithWeb.KithUI` | `lib/kith_web/components/kith_ui.ex` | Domain-specific (avatar, contact_badge, stat_card, etc.) |
| `KithWeb.CoreComponents` | `lib/kith_web/components/core_components.ex` | **Legacy** — kept during migration |
| `KithWeb.KithComponents` | `lib/kith_web/components/kith_components.ex` | **Legacy** — kept during migration |

During migration, templates may use module-qualified syntax to avoid conflicts: `<KithWeb.UI.button>` vs `<.button>`.

### Semantic Status Colors

| Status | Color | Use |
|---|---|---|
| Success | Green | Completed actions, positive indicators |
| Warning | Amber | Caution states, pending items |
| Error | Red | Failures, destructive action warnings |
| Info | Blue | Neutral information, help text |

Each status has three tokens: `--color-{status}`, `--color-{status}-foreground`, `--color-{status}-subtle` (background tint).

---

## 7. Animation Conventions

### Timing

| Duration | Use Case |
|---|---|
| 150ms | Hover states, color transitions |
| 200ms | Button presses, dropdown open |
| 300ms | Modal enter, page transitions |

### Easing

- **Entering:** `ease-out` (fast start, gentle stop)
- **Leaving:** `ease-in` (gentle start, fast stop)
- **Snappy interactions:** `var(--ease-snappy)` = `cubic-bezier(0.2, 0, 0, 1)`

### Required Behaviors

- Buttons: `active:scale-[0.98]` press effect
- Modals: backdrop blur + scale+fade animation
- Flash toasts: slide-in from top-right, auto-dismiss with progress bar
- Dropdowns: scale+fade, 200ms
- Tabs: amber underline transition

### Accessibility

- All animations must respect `prefers-reduced-motion`. Use `motion-safe:` prefix for decorative animations.
- Focus rings use `--color-border-focus` (amber-500).

### Plugin

`tailwindcss-animate` is available as a Tailwind v4 plugin for animation utilities (`animate-in`, `animate-out`, `fade-in`, `slide-in-from-top`, etc.).

---

## 8. Component Variant Patterns

All new components in `KithWeb.UI` follow the **variant pattern** for consistent API design.

### Pattern

```elixir
attr :variant, :string, default: "primary", values: ~w(primary secondary ghost danger outline)
attr :size, :string, default: "md", values: ~w(sm md lg)

def button(assigns) do
  ~H"""
  <button class={[
    "base-classes",
    variant_classes(@variant),
    size_classes(@size)
  ]}>
    {render_slot(@inner_block)}
  </button>
  """
end
```

### Rules

1. **Variant as string attr** — not atoms, for HEEx template ergonomics
2. **Explicit `values` list** — compile-time validation via Phoenix.Component
3. **Default variant is always first** — `"primary"` for buttons, `"default"` for badges
4. **Size scale:** `sm` / `md` / `lg` — three sizes, `md` default
5. **No conditional nesting** — use a flat list of CSS classes via `class={[...]}` pattern

### Flop Integration

Server-side sorting, filtering, and pagination via Flop. Schemas declare filterable/sortable fields:

```elixir
@derive {Flop.Schema,
  filterable: [:display_name, :email],
  sortable: [:display_name, :inserted_at],
  default_order: %{order_by: [:display_name], order_directions: [:asc]}}
```

Use `Kith.FlopConfig` as the named backend for Flop function calls.

---

*This document is maintained by the Kith core team. Raise questions or propose amendments via PR against `docs/frontend-conventions.md`.*
