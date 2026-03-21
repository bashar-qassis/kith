# Kith Frontend UI/UX Revamp Plan

## Context

Kith's current frontend uses Phoenix LiveView + Tailwind CSS v4 + daisyUI with default Phoenix styling. While functional, the UI feels generic and unpolished — lacking the premium, mature quality expected of a production application. The goal is a complete visual rewrite that makes Kith feel like a **refined, warm, enterprise-grade Personal Relationship Manager** — inspired by Linear's precision, Notion's personality, and Stripe's refinement, but with a distinctive warmth appropriate for an app about personal relationships.

**What changes:** All frontend templates, components, and styles.
**What stays:** All backend contexts, Ecto schemas, LiveView event handlers, business logic, Alpine.js scope boundary rules, RTL conventions, Policy.can?/3 patterns, and the 3-level component hierarchy.

---

## Design Direction: "Warm Precision"

**Tone:** Like opening a beautifully bound personal notebook. Warm, refined, intentional.

| Attribute | Choice |
|-----------|--------|
| **Neutrals** | Stone palette (warm gray) — not cold zinc |
| **Accent** | Amber/Copper — warm, personal, distinctive |
| **Surfaces** | Soft cream tones (stone-50), not pure white |
| **Typography** | Plus Jakarta Sans (display + body) + Geist Mono (code) |
| **Borders** | 1px warm stone-200/300, subtle |
| **Shadows** | Warm-tinted, low opacity (`shadow-card`, `shadow-dropdown`) |
| **Radii** | 8px cards, 6px inputs, 9999px badges |
| **Spacing** | 8px grid system, generous whitespace |
| **Motion** | 200-300ms transitions, ease-out entering, ease-in leaving |
| **Dark mode** | Deep warm tones (stone-900/950 surfaces), amber accent preserved |
| **Icons** | Heroicons (already in use) |

**Typography scale (Plus Jakarta Sans):**
- Weight: 400 body, 500 emphasis/labels, 600 headings. Never 700.
- `tracking-tight` on headings >= text-2xl only
- `leading-relaxed` body, `leading-snug` headings

**What makes it unforgettable:** The warmth. Most SaaS apps use cold zinc/slate. Kith's stone + amber palette immediately feels personal, human, and premium — matching its purpose as a *relationship* manager.

---

## Stack Changes

| Layer | Current | New | Rationale |
|-------|---------|-----|-----------|
| Component library | daisyUI | Custom components (Chelekom-inspired patterns) | daisyUI is too generic for premium; custom gives full control |
| Typography | System fonts | Plus Jakarta Sans + Geist Mono (self-hosted) | Distinctive, warm character |
| Neutral palette | Mixed (daisyUI base-100/200/300) | Stone palette via semantic tokens | Warm, cohesive, matches PRM personality |
| Color system | daisyUI theme variables | Tailwind v4 `@theme` semantic tokens (OKLCH) | Full control, dark mode via variable swap |
| Data tables | Manual pagination | Flop + Flop Phoenix | Server-side sort/filter/pagination |
| Animations | Minimal | Phoenix.LiveView.JS + CSS transitions + tailwindcss-animate | Premium micro-interactions |
| New feature | — | Command palette (Cmd+K) | Defining UX differentiator |

**Kept:** Alpine.js (UI chrome), Heroicons, esbuild, LiveView architecture, Tailwind v4 (already on 4.1.12).

---

## Migration Strategy

**daisyUI coexistence:** daisyUI classes and custom classes can coexist because daisyUI is just a Tailwind plugin. We build new components alongside old ones, migrate pages one at a time, then remove daisyUI in the final phase.

**Parallel component modules:** Create `KithWeb.UI` (new core) and `KithWeb.KithUI` (new domain) alongside existing `CoreComponents` and `KithComponents`. Migrate pages to use new modules. Delete old modules last.

**Chelekom approach:** Manually adapt patterns and APIs from Mishka Chelekom — don't install via CLI. Cherry-pick the ~20 components Kith needs. This avoids dependency bloat and gives full styling control.

---

## Phase 0: Design Foundation
**Complexity: L | Risk: Low (additive, nothing breaks)**

Build all infrastructure that subsequent phases depend on. Nothing visible changes — daisyUI stays active.

### Steps

**0.1: Self-host fonts**
- Download Plus Jakarta Sans Variable (woff2) and Geist Mono (woff2)
- Place in `priv/static/fonts/plus-jakarta-sans/` and `priv/static/fonts/geist-mono/`
- Add `@font-face` declarations to `assets/css/app.css` with `font-display: swap`
- `KithWeb.static_paths/0` already includes `fonts` (line 20 of `lib/kith_web.ex`)

**0.2: Design token system**
- Add `@theme` block in `assets/css/app.css` with semantic OKLCH tokens:
  - **Surfaces:** `--surface`, `--surface-elevated`, `--surface-sunken`, `--surface-overlay`
  - **Text:** `--text-primary` (stone-900), `--text-secondary` (stone-600), `--text-tertiary` (stone-500), `--text-disabled`
  - **Borders:** `--border` (stone-200), `--border-subtle` (stone-100), `--border-focus` (amber-500)
  - **Accent:** `--accent` (amber-600), `--accent-hover` (amber-700), `--accent-foreground` (white), `--accent-subtle` (amber-50)
  - **Semantic:** `--success`, `--warning`, `--error`, `--info` + foreground variants
  - **Radius:** `--radius-sm` (4px), `--radius-md` (6px), `--radius-lg` (8px), `--radius-full` (9999px)
  - **Shadows:** `--shadow-card`, `--shadow-dropdown`, `--shadow-modal` (warm-tinted)
  - **Font:** `--font-sans: 'Plus Jakarta Sans Variable', ...`, `--font-mono: 'Geist Mono', ...`
  - **Easing:** `--ease-snappy: cubic-bezier(0.2, 0, 0, 1)`
- Dark mode overrides via `[data-theme=dark]` selector (existing mechanism)
- Keep existing daisyUI `@plugin` directives intact for now

**0.3: Add tailwindcss-animate**
- Add to `assets/package.json`
- Configure as Tailwind v4 `@plugin`

**0.4: Add Flop + Flop Phoenix**
- Add to `mix.exs`: `{:flop, "~> 0.26"}`, `{:flop_phoenix, "~> 0.23"}`
- Create `Kith.Flop` configuration module
- Backend plumbing only — no page changes

**0.5: Update frontend-conventions.md**
- Document new token system, animation conventions, component variant patterns

### Files
- `assets/css/app.css` — Add `@theme` tokens and `@font-face`
- `assets/package.json` — Add tailwindcss-animate
- `mix.exs` — Add flop, flop_phoenix
- `priv/static/fonts/` — New font files
- `docs/frontend-conventions.md` — Update

### Verification
- `mix deps.get && mix compile` succeeds
- App renders identically (daisyUI still active)
- Font files serve from `/fonts/` endpoint
- New CSS custom properties visible in browser DevTools

---

## Phase 1: Core Components Rewrite
**Complexity: XL | Risk: Medium**

Create the new component library with the Warm Precision design system.

### Step 1.1: Create `KithWeb.UI` module
**File:** `lib/kith_web/components/ui.ex`

New core primitives built on semantic tokens:

| Component | Variants/Notes |
|-----------|---------------|
| `button/1` | primary, secondary, ghost, danger, outline; sizes sm/md/lg; `active:scale-[0.98]` press effect |
| `input/1` | All HTML types, labels above fields, focus ring in `--accent`, inline validation on blur |
| `select/1` | Custom styled, stone border, amber focus |
| `textarea/1` | With optional character counter slot |
| `checkbox/1` | Custom styled with amber accent |
| `simple_form/1` | Form wrapper |
| `icon/1` | Same Heroicons pattern (reuse from current `core_components.ex`) |
| `badge/1` | default, success, warning, error, info; outlined variant |
| `flash/1` | Slide-in toast from top-right, auto-dismiss, progress bar |
| `header/1` | Page header with breadcrumb slot |
| `table/1` | Clean table — no zebra stripes, subtle row hover |
| `modal/1` | Backdrop blur, scale+fade animation, focus trap |
| `dropdown/1` | Positioned menu with keyboard nav |
| `tooltip/1` | CSS-only tooltip |
| `skeleton/1` | Loading placeholder with `animate-pulse` in stone-200 |
| `kbd/1` | Keyboard shortcut display (e.g., "Cmd+K") |
| `separator/1` | Horizontal rule, optional label |
| `tabs/1` | Underline-style tab nav with amber active indicator |
| `card/1` | Elevated surface with `--shadow-card`, stone border |

### Step 1.2: Create `KithWeb.KithUI` module
**File:** `lib/kith_web/components/kith_ui.ex`

Domain-specific components:

| Component | Notes |
|-----------|-------|
| `avatar/1` | Same API, warm color ring on hover, stone shadow |
| `contact_badge/1` | Refined chip with avatar |
| `tag_badge/1` | Pill with new color system |
| `reminder_row/1` | Heroicons instead of emoji, clean layout |
| `stat_card/1` | Extracted from dashboard (currently private in `DashboardLive.Index`) |
| `section_header/1` | Refined typography |
| `empty_state/1` | Human-voiced copy, illustration area, single CTA |
| `role_badge/1` | Warm color coding |
| `emotion_badge/1` | Warm color coding |
| `date_display/1` | Same logic, new `<time>` styling |
| `relative_time/1` | Same logic, new styling |
| `command_palette/1` | New — search/navigation overlay |

### Step 1.3: Wire into KithWeb
- Update `lib/kith_web.ex` `html_helpers/0`: add `import KithWeb.UI` and `import KithWeb.KithUI`
- Keep old imports temporarily, use `:except` to handle name conflicts
- During migration, templates can use module-qualified syntax: `<KithWeb.UI.button>` vs `<.button>`

### Step 1.4: Component preview page (dev-only)
- Create a dev-only LiveView at `/dev/components` rendering every component in all variants
- Visual verification without affecting production

### Files
- `lib/kith_web/components/ui.ex` — **Create** (new core)
- `lib/kith_web/components/kith_ui.ex` — **Create** (new domain)
- `lib/kith_web.ex` — Wire new imports

### Verification
- All new components render in isolation (preview page)
- Existing pages still work with old components
- `mix compile` — zero warnings
- RTL verified on all new components
- Dark mode verified on all new components

---

## Phase 2: App Shell & Layout Rewrite
**Complexity: L | Risk: Medium-High (affects every page)**

Rewrite the application shell. Highest single-change impact.

### Step 2.1: Update root.html.heex
**File:** `lib/kith_web/components/layouts/root.html.heex`
- Body classes: `font-sans antialiased bg-surface text-text-primary`
- Keep existing theme script block (works well)
- Custom scrollbar styling (thin, warm-tinted)

### Step 2.2: Rewrite `Layouts.app/1`
**File:** `lib/kith_web/components/layouts.ex`

New sidebar design (Linear-inspired, warm):
- 240px expanded / 60px collapsed, smooth transition
- Background: `var(--surface-sunken)` — slightly warmer than main
- 1px border-e in `var(--border-subtle)`
- Logo: "Kith" wordmark in Plus Jakarta Sans semibold, no box
- Nav items: icon + label, active state = amber start-border + subtle bg
- Hover: `bg-surface-elevated` transition 150ms
- User footer: avatar + name + dropdown
- Mobile: bottom tab bar (restyle, same structure)
- `aria-current="page"` on active nav items

### Step 2.3: Delayed topbar
**File:** `assets/js/app.js`
- 200ms delay before showing progress bar (prevents flash on fast loads)
- Thin amber-colored bar at top

### Step 2.4: Flash + theme toggle
- Flash: slide-in from top-right with new `KithWeb.UI.flash/1`
- Theme toggle: pill toggle in sidebar or user dropdown

### Step 2.5: Create `Layouts.auth/1`
- Centered card layout for auth pages
- "Kith" wordmark, clean card on warm surface

### Files
- `lib/kith_web/components/layouts.ex` — Complete rewrite
- `lib/kith_web/components/layouts/root.html.heex` — Update
- `assets/js/alpine/sidebar.js` — Update class names
- `assets/js/app.js` — Delayed topbar

### Verification
- Every authenticated page renders in new shell
- Sidebar nav works (all links, active states, collapse)
- Mobile layout works (responsive breakpoints)
- Theme toggle works
- Flash messages display correctly
- RTL + dark mode verified

---

## Phase 3: Auth Pages
**Complexity: M | Risk: Low (isolated pages)**

10 LiveView modules — standalone, use `Layouts.auth/1`.

### Pages
1. `lib/kith_web/live/user_live/login.ex`
2. `lib/kith_web/live/user_live/registration.ex`
3. `lib/kith_web/live/user_live/forgot_password.ex`
4. `lib/kith_web/live/user_live/reset_password.ex`
5. `lib/kith_web/live/user_live/confirmation.ex`
6. `lib/kith_web/live/user_live/confirm_email_pending.ex`
7. `lib/kith_web/live/user_live/totp_setup.ex`
8. `lib/kith_web/live/user_live/totp_challenge.ex`
9. `lib/kith_web/live/user_live/invitation_acceptance.ex`
10. `lib/kith_web/live/user_live/settings.ex`

### Design
- Centered card on warm surface: `max-w-md mx-auto`, `--surface-elevated`, warm shadow
- "Kith" wordmark logo at top
- Clean form inputs (labels above, amber focus ring)
- OAuth buttons: outlined with provider logos
- TOTP: larger code input boxes, QR in centered card
- Password strength meter: amber-colored bar (update Alpine module)
- Replace all daisyUI classes with `KithWeb.UI` components

### Verification
- All auth flows work end-to-end
- Form validation inline errors display correctly
- RTL + dark mode verified on login page

---

## Phase 4: Dashboard
**Complexity: M | Risk: Low**

**File:** `lib/kith_web/live/dashboard_live/index.ex` (212 lines, inline render)

### Design
- Header: "Good morning, {name}" greeting
- Stats cards: 4-column grid, `stat_card/1` with subtle stone borders, no heavy backgrounds
- Recent contacts: Clean list — avatar, name, tags, relative time
- Activity feed: Timeline-style with small type icons, subtle stone connector line
- Immich banner: Amber-tinted left border callout (not full background)
- Skeleton loading states for async data

### Changes
- Extract `stat_card/1` from private function to `KithWeb.KithUI`
- Replace all daisyUI classes
- Add skeleton screens during initial mount

### Verification
- Dashboard renders with real data and empty states
- Immich banner shows/dismisses
- Stats cards link correctly
- Skeleton loading visible during mount

---

## Phase 5: Contact List & Trash
**Complexity: XL | Risk: Medium**

Most complex page — search, sort, filter, bulk actions, tag filtering, pagination.

### Files
- `lib/kith_web/live/contact_live/index.ex` (279 lines)
- `lib/kith_web/live/contact_live/index.html.heex` (280 lines)
- `lib/kith_web/live/contact_live/trash.ex` (172 lines)

### Step 5.1: Integrate Flop
- Create Flop schema for contacts
- Replace manual search/sort/pagination with Flop queries

### Step 5.2: Redesign contact list
- **Search bar:** Full-width, search icon, stone border, amber focus
- **Filters:** Collapsible filter bar (progressive disclosure), active count badge
- **Table:** Clean — no zebra, subtle stone-50 hover, uppercase text-xs headers
- **Bulk action bar:** Floating sticky bar at bottom (Linear-style) when items selected
- **Tag filter:** Horizontal chip bar, selected = amber-filled
- **Pagination:** Flop-powered (cursor-based or page numbers)
- **Empty state:** Warm empty state with CTA

### Step 5.3: Redesign trash page
- Same table style, amber-left-border warning banner

### Verification
- Search, sort, filter, tag filter all work
- Bulk select/actions work
- Pagination works
- Trash restore/delete works
- RTL + dark mode verified

---

## Phase 6: Contact Show (Profile) Page
**Complexity: XL | Risk: Medium**

Most complex page — sidebar + tabbed content + 8 LiveComponents.

### Files (12 modules)
- `lib/kith_web/live/contact_live/show.ex` + `show.html.heex`
- `lib/kith_web/live/contact_live/notes_list_component.ex`
- `lib/kith_web/live/contact_live/activities_list_component.ex`
- `lib/kith_web/live/contact_live/calls_list_component.ex`
- `lib/kith_web/live/contact_live/life_events_list_component.ex`
- `lib/kith_web/live/contact_live/photos_gallery_component.ex`
- `lib/kith_web/live/contact_live/documents_list_component.ex`
- `lib/kith_web/live/contact_live/addresses_component.ex`
- `lib/kith_web/live/contact_live/contact_fields_component.ex`
- `lib/kith_web/live/contact_live/relationships_component.ex`
- `lib/kith_web/live/contact_live/reminders_component.ex`

### Design
- **Sidebar (start):** Large avatar (hover upload state), name + favorite, metadata as `<dl>`, tags inline, collapsible sub-cards for addresses/fields/relationships/reminders
- **Main area (end):** Amber underline tabs, fade transition on switch
- **Notes:** Card-based with markdown preview
- **Photos:** Grid gallery with hover overlay
- **Life events:** Timeline layout with stone connector line
- **Activities/Calls:** Clean list with type icons and relative time

### Verification
- Profile renders with full data
- All tabs switch, each sub-component allows CRUD
- Tag add/remove, favorite toggle, archive/delete work
- RTL + dark mode verified

---

## Phase 7: Contact New/Edit & Merge
**Complexity: L | Risk: Low-Medium**

### Files
- `lib/kith_web/live/contact_live/new.ex`
- `lib/kith_web/live/contact_live/edit.ex`
- `lib/kith_web/live/contact_live/form_component.ex`
- `lib/kith_web/live/contact_live/merge.ex` (471 lines — most complex form)

### Design
- **Forms:** Sections with clear headings, labels above, amber focus rings, inline validation on blur
- **Avatar upload:** Drag-and-drop area with visual feedback
- **Merge wizard:** Horizontal stepper (numbered circles + connecting line), 4 steps with side-by-side comparison

### Verification
- Create/edit/merge flows work end-to-end
- Avatar upload works
- Form validation displays correctly

---

## Phase 8: Reminders & Settings
**Complexity: L | Risk: Low**

### Reminders
**File:** `lib/kith_web/live/reminder_live/upcoming.ex`
- 30/60/90 day toggle: Pill-shaped button group
- Grouped by date with stone dividers
- Heroicons instead of emoji (current code uses unicode emoji)
- Action buttons: resolve/dismiss

### Settings (7 pages)
- `settings_live/settings_layout.ex` — Sidebar nav restyled (amber active indicator)
- `settings_live/account.ex` — Card-based sections
- `settings_live/tags.ex` + `tags.html.heex` — Inline editable tag list
- `settings_live/integrations.ex` — Connection status cards
- `settings_live/import.ex` — File upload area with progress
- `settings_live/export.ex` — Clean action cards
- `settings_live/audit_log.ex` — Flop-powered data table

### Verification
- All settings pages render and save correctly
- Reminders 30/60/90 filter works
- Audit log paginates
- RTL + dark mode verified

---

## Phase 9: Command Palette, Admin & Error Pages
**Complexity: L | Risk: Low-Medium**

### Step 9.1: Command palette
- Create `assets/js/hooks/command_palette.js` — LiveView hook for Cmd+K
- Create `assets/js/alpine/command_palette.js` — Open/close state, keyboard nav
- Add `command_palette/1` component to `Layouts.app/1` (available on every authenticated page)
- Server-side: Add `handle_event("command_palette_search", ...)` to a shared hook or layout module
- Sections: Recent, Contacts (fuzzy search), Pages, Actions
- `<.kbd>` hint ("Cmd+K") in sidebar

### Step 9.2: Admin Oban dashboard
**File:** `lib/kith_web/live/admin_live/oban_dashboard.ex`
- Restyle tables and stats with new tokens

### Step 9.3: Error pages (403, 404, 500)
**Files:** `lib/kith_web/controllers/error_html/*.html.heex`
- Currently use CDN Tailwind — switch to compiled app.css (static, served even during errors)
- Centered card, relevant icon, warm message, action button

### Step 9.4: Immich review
**File:** `lib/kith_web/live/contact_live/immich_review.ex`
- Restyle with new tokens

### Verification
- Cmd+K opens palette on all pages, search returns contacts, Escape closes
- Admin page renders
- Error pages render (test by visiting invalid routes)

---

## Phase 10: Cleanup & Polish
**Complexity: M | Risk: Low**

### Step 10.1: Remove daisyUI
- Delete `assets/vendor/daisyui.js` and `assets/vendor/daisyui-theme.js`
- Remove `@plugin` directives from `assets/css/app.css`
- Grep entire codebase for remaining daisyUI classes and replace

### Step 10.2: Remove old component modules
- Delete `lib/kith_web/components/core_components.ex`
- Delete `lib/kith_web/components/kith_components.ex`
- Rename `KithWeb.UI` -> `KithWeb.CoreComponents` (or keep and update imports)
- Clean up `lib/kith_web.ex` imports

### Step 10.3: Final audit
- Consistent spacing, typography, color across all pages
- All transitions smooth (200-300ms, ease-out entering)
- Keyboard accessibility: tab order, focus rings, Escape to close
- Full RTL audit (Arabic) on every page
- Full dark mode audit on every page
- CSS bundle size check (should be smaller without daisyUI)
- `prefers-reduced-motion` respected everywhere

### Step 10.4: Documentation
- Update `docs/frontend-conventions.md` — final component names, token system, animation rules
- Remove all daisyUI references

### Verification
- Full app walkthrough: light + dark mode
- Full app walkthrough: RTL (Arabic)
- Zero console errors
- All existing tests pass
- `mix test` green

---

## Dependency Graph & Parallelization

```
Phase 0 (Foundation)
    │
    ▼
Phase 1 (Components)
    │
    ▼
Phase 2 (App Shell)
    │
    ├──────────┬──────────┬──────────┐
    ▼          ▼          ▼          ▼
Phase 3    Phase 4    Phase 7    Phase 8
(Auth)     (Dashboard)(Forms)    (Settings)
    │          │          │          │
    │          ▼          │          │
    │       Phase 5      │          │
    │       (List)       │          │
    │          │          │          │
    │          ▼          │          │
    │       Phase 6      │          │
    │       (Profile)    │          │
    │          │          │          │
    ├──────────┴──────────┴──────────┤
    ▼                                ▼
Phase 9 (Cmd Palette/Admin/Errors)
    │
    ▼
Phase 10 (Cleanup & Polish)
```

**Critical path:** 0 → 1 → 2 → 5 → 6 → 10
**Parallelizable after Phase 2:** 3, 4, 7, 8 are independent page migrations.

---

## Key Existing Code to Reuse

| What | Where | Reuse How |
|------|-------|-----------|
| `icon/1` component | `core_components.ex:L189-215` | Copy into `ui.ex` — Heroicons integration unchanged |
| Avatar color hashing | `kith_components.ex:L17-35` | Copy `name_to_color/1` and `initials/1` into `kith_ui.ex` |
| Theme toggle JS | `layouts/root.html.heex` | Keep existing localStorage + `data-theme` mechanism |
| Alpine sidebar | `assets/js/alpine/sidebar.js` | Same logic, update class names |
| Trix editor hook | `assets/js/hooks/trix_editor.js` | Keep unchanged |
| Policy.can?/3 gates | All LiveView modules | Keep all permission checks unchanged |
| RTL logical properties | All templates | Continue using `ms-`, `me-`, `ps-`, `pe-`, `border-s-`, `border-e-` |

---

## Verification Strategy

After each phase:
1. `mix compile` — zero warnings
2. `mix test` — all green
3. Visual check: light mode, dark mode, RTL
4. Functional check: core user flows still work
5. Browser DevTools: no console errors, no broken network requests

Final verification (Phase 10):
1. Full walkthrough of every page in light + dark + RTL
2. Keyboard navigation audit (tab through all interactive elements)
3. `mix test` — all green
4. CSS bundle size comparison (before/after daisyUI removal)
5. Lighthouse accessibility score check
