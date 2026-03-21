# Phase 11: Frontend — LiveView Screens & Components

> **Status:** Implemented
> **Depends on:** Phase 01 (Foundation), Phase 02 (Auth), Phase 03 (Domain), Phase 04-05 (Contacts & Sub-entities), Phase 06 (Reminders), Phase 07 (Integrations), Phase 08 (Settings)
> **Blocks:** Phase 14 (QA & E2E Testing)

## Overview

This phase implements all LiveView screens, function components, navigation, and frontend conventions for the Kith PRM application. It is the UI layer that binds LiveViews to the existing domain contexts, auth system, and integration backends built in prior phases. Every screen uses RTL-safe Tailwind logical properties, ex_cldr for date/number formatting, and respects the Policy-based authorization model.

---

## Tasks

### TASK-11-01: Root Layout & HTML Shell
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-01-02 (Foundation dependencies)
**Description:**
Create the root layout template `root.html.heex` with:
- `<html dir="<%= html_dir(@locale) %>" lang="<%= @locale %>">` where `html_dir/1` is a helper returning `"rtl"` for Arabic, Hebrew, Persian, Urdu and `"ltr"` for all other locales.
- `<meta charset="utf-8">`, viewport meta tag, CSP nonce attribute on script/style tags.
- Include TailwindCSS build output, Alpine.js (installed via npm), Heroicons (Phoenix built-in).
- Create `assign_locale/2` plug that reads user preference from `current_user.locale` (falling back to account locale, then `"en"`), sets Gettext locale, sets ex_cldr locale, and assigns `@locale` to the connection/socket.

**Acceptance Criteria:**
- [ ] `root.html.heex` renders with correct `dir` and `lang` attributes based on user locale
- [ ] `html_dir/1` correctly returns `"rtl"` for RTL locales
- [ ] `assign_locale/2` plug sets Gettext and ex_cldr locales
- [ ] Alpine.js loads and initializes on page load
- [ ] CSP nonce is present on inline scripts

**Safeguards:**
> :warning: Do not hardcode `dir="ltr"` — always derive from locale. Missing RTL support in the root layout cascades to every screen.

**Notes:**
- Alpine.js must be installed via npm and bundled by esbuild, not loaded from a CDN (CSP would block it).
- The `assign_locale` plug must run after `fetch_current_user` in the pipeline so it has access to user preferences.

---

### TASK-11-02: Frontend Conventions Document
**Priority:** Critical
**Effort:** S
**Depends on:** None
**Description:**
Create and commit `docs/frontend-conventions.md` — this is one of the Phase 00 pre-code gates. The document must define:

- **Level 1 (LiveView modules):** One per route, owns socket state and handle_event callbacks. No rendering logic in the module itself beyond `render/1` delegating to templates. Examples: `ContactListLive`, `ContactProfileLive`, `DashboardLive`.
- **Level 2 (LiveComponents):** `use Phoenix.LiveComponent`, own `handle_event/3`, own data loading in `update/2` or `mount/1`. Independent lifecycle. Examples: `NotesListComponent`, `ActivitiesListComponent`, `PhotosGalleryComponent`, `ImmichReviewComponent`.
- **Level 3 (Function components):** `def component_name(assigns)`, no state, pure render. Examples: `.contact_badge`, `.tag_badge`, `.reminder_row`, `.card`, `.avatar`.
- **Alpine.js scope boundary:** UI chrome only — dropdowns, tooltips, clipboard copy, sidebar collapse, toggle state, lightbox. NEVER reads/writes server state. NEVER submits forms. All data mutations go through LiveView `phx-click`, `phx-submit`, or explicit API calls.
- **RTL-safe Tailwind:** Use logical properties throughout (`ms-`, `me-`, `ps-`, `pe-`, `bs-`, `be-`, `start-`, `end-`). NEVER use `ml-`, `mr-`, `pl-`, `pr-`, `left-`, `right-` in templates.
- **Policy integration pattern:** `Kith.Policy.can?/3` called in LiveView `mount/3` for page-level access. In templates, use `authorized?/3` helper to conditionally render controls. Hide (not gray) restricted controls.

**Acceptance Criteria:**
- [ ] `docs/frontend-conventions.md` committed to repository
- [ ] All three component levels documented with examples
- [ ] Alpine.js scope boundary explicitly stated as a coding standard
- [ ] RTL Tailwind rules enumerated with banned property list
- [ ] Policy integration pattern documented with code examples

**Safeguards:**
> :warning: This document is a pre-code gate. No contact profile LiveView should be merged before this document is reviewed and committed.

**Notes:**
- Reference the product spec Section 12 (Frontend Architecture) for the canonical hierarchy definition.

---

### TASK-11-03: RTL & i18n Setup
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-11-01
**Description:**
Configure Gettext with default locale `"en"`. Configure ex_cldr with locales to support (at minimum: `en`, `fr`, `ar`, `de`, `es`, `pt`, `ja`, `zh`). Create `KithWeb.Cldr` module using `use Cldr, locales: [...]`. Ensure all date/time/number/currency rendering uses:
- `Cldr.Date.to_string!/2` for dates
- `Cldr.Number.to_string!/2` for numbers
- `Cldr.Currency.to_string!/2` for currency

Enforce Tailwind logical properties throughout. Consider adding a custom Credo check or CI lint that flags usage of `ml-`, `mr-`, `pl-`, `pr-`, `left-`, `right-` in `.heex` templates.

**Acceptance Criteria:**
- [ ] `KithWeb.Cldr` module created with supported locales
- [ ] Gettext configured with `"en"` as default locale
- [ ] At least one RTL locale (`ar`) is functional end-to-end
- [ ] Lint or CI check flags banned directional Tailwind utilities in templates
- [ ] Date/number helpers available for use in templates

**Safeguards:**
> :warning: Do not use Elixir's `Calendar.strftime/3` or raw string interpolation for dates — always go through ex_cldr from the first template. Retrofitting i18n is extremely expensive.

**Notes:**
- RTL test checkpoint: after each major screen is built, verify in Arabic locale using browser DevTools (`document.documentElement.dir = "rtl"`).

---

### TASK-11-04: Function Component Library
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-11-02, TASK-11-03
**Description:**
Create `KithWeb.Components.Core` module (separate from Phoenix-generated `core_components.ex`) with these function components:

| Component | Purpose |
|-----------|---------|
| `.avatar` | Renders user/contact avatar with initials fallback when no image |
| `.contact_badge` | Avatar + name chip, links to contact profile |
| `.tag_badge` | Colored tag pill |
| `.reminder_row` | Reminder with type icon + formatted date |
| `.card` | Standard card container with optional header/footer slots |
| `.section_header` | Section title with optional action button slot |
| `.empty_state` | Icon + message + optional CTA action |
| `.role_badge` | Admin/editor/viewer role chip with color coding |
| `.emotion_badge` | Emotion label chip |
| `.date_display` | Renders date using ex_cldr, respects user locale |
| `.relative_time` | Renders relative time (e.g., "3 days ago") using ex_cldr |

All components must use Tailwind logical properties. All must accept an `id` attribute where applicable. All date/time components must use ex_cldr formatting.

**Acceptance Criteria:**
- [ ] All 11 components implemented in `KithWeb.Components.Core`
- [ ] `.avatar` renders initials fallback (first letter of first + last name) when no image URL
- [ ] `.date_display` and `.relative_time` respect `@locale` assign
- [ ] All components use logical Tailwind properties (no directional utilities)
- [ ] Components render correctly in both LTR and RTL layouts

**Safeguards:**
> :warning: Do not duplicate Phoenix's built-in `core_components.ex` — extend it. Avoid creating components that manage their own state (those should be LiveComponents at Level 2).

**Notes:**
- `.avatar` initials: take first character of `first_name` + first character of `last_name`. If only one name, use first two characters. If no name, use "?".
- `.tag_badge` color can be derived from a hash of the tag name for consistent coloring.

---

### TASK-11-05: Navigation Layout & App Shell
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-11-01, TASK-11-04
**Description:**
Implement the app shell with:
- **Desktop sidebar:** Collapsible via Alpine.js `x-data="{open: true}"`. Top-level nav items: Dashboard, Contacts, Upcoming Reminders, Settings. Active route highlighting (compare `@current_path` or use Phoenix verified routes). Immich `needs_review` badge count on Dashboard nav item (only if Immich enabled).
- **Mobile bottom nav:** Condensed bottom bar with icons for the same four sections. Responsive breakpoint at `md:`.
- **Sidebar footer:** Current user avatar + name, dropdown menu (Settings link, Log out link) using Alpine.js for dropdown toggle.
- **Main content area:** Rendered inside the app shell, scrollable.

**Acceptance Criteria:**
- [ ] Desktop sidebar renders with all four nav items
- [ ] Active route is visually highlighted
- [ ] Sidebar collapse/expand works via Alpine.js toggle
- [ ] Mobile bottom nav appears on small screens, sidebar hidden
- [ ] Immich needs_review badge count renders next to Dashboard (hidden if zero or Immich disabled)
- [ ] User avatar + name in sidebar footer with working dropdown
- [ ] Layout mirrors correctly in RTL (sidebar on right side)

**Safeguards:**
> :warning: Sidebar collapse state should persist per session (Alpine.js `x-init` reading from localStorage is acceptable for this — it is UI chrome, not server state).

**Notes:**
- Use `Phoenix.LiveView.Helpers.live_redirect` or verified routes for navigation links to enable LiveView navigation without full page reloads.
- Badge count fetched via a lightweight context call in the layout's `on_mount` hook.

---

### TASK-11-06: Policy Integration in LiveView
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-02-21 (Kith.Policy module)
**Description:**
Establish the pattern for policy enforcement in LiveViews:
1. In `mount/3`, call `Kith.Policy.can?(socket.assigns.current_user, action, resource)` for the primary action of the view.
2. On `{:error, :unauthorized}` return, `push_redirect` to a 403 error page.
3. Create `KithWeb.PolicyHelper` module with `authorized?(user, action, resource)` convenience wrapper that returns a boolean (true if `{:ok, :authorized}`, false otherwise). Import this in all LiveView/component templates.
4. In templates: `<%= if authorized?(@current_user, :edit_contact, @contact) do %>` — hide (not gray) restricted controls.

**Acceptance Criteria:**
- [ ] `KithWeb.PolicyHelper` module created with `authorized?/3` function
- [ ] Pattern established: `mount/3` checks policy and redirects on unauthorized
- [ ] Viewer role users cannot see edit/delete buttons on contact profiles
- [ ] Admin-only settings sections are hidden for non-admin users
- [ ] 403 redirect works correctly (no crash, clear error page)

**Safeguards:**
> :warning: Policy checks in templates are UI-only — the context layer MUST also enforce authorization. Template hiding prevents UX confusion but is not a security boundary.

**Notes:**
- `Kith.Policy.can?/3` is synchronous (no DB call) — it checks the user's role against the action. The resource argument for container-level checks (like `:manage_account`) can be the atom `:account_settings` or the `%Account{}` struct.

---

### TASK-11-07: Error Pages
**Priority:** High
**Effort:** XS
**Depends on:** TASK-11-01
**Description:**
Create error pages:
- **404:** "Contact not found" friendly message with a link back to contacts list. Handles both missing routes and missing resources.
- **403:** "You don't have permission to access this page." Explains role limitation. Links to account admin (if viewer) or home page.
- **500:** Generic "Something went wrong" message. No stack trace in production. Include a reference ID for support.

**Acceptance Criteria:**
- [ ] 404 page renders with friendly message and back-to-contacts link
- [ ] 403 page renders with role explanation and navigation link
- [ ] 500 page renders without stack trace in prod
- [ ] All error pages use the app's visual style (not Phoenix default)
- [ ] Error pages work in both LTR and RTL layouts

**Safeguards:**
> :warning: Do not render any internal error details on the 500 page in production. Use `Plug.Exception` protocol for custom error rendering.

---

### TASK-11-08: Registration Screen
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-02-04 (Account registration), TASK-11-01
**Description:**
LiveView at `/users/register`. Fields: email, password, password confirmation. Password strength indicator implemented with Alpine.js (checks length, character variety — UI chrome only, not a security gate). Optional terms checkbox (if configured). On submit: creates account + user, redirects to email verification page (if `SIGNUP_DOUBLE_OPTIN=true`) or dashboard. Registration link hidden if `DISABLE_SIGNUP=true`.

**Acceptance Criteria:**
- [ ] Registration form renders with email, password, password confirmation fields
- [ ] Password strength indicator updates as user types (Alpine.js)
- [ ] Successful registration redirects appropriately based on `SIGNUP_DOUBLE_OPTIN`
- [ ] Form shows validation errors inline (LiveView `phx-change` validation)
- [ ] Registration page not accessible when `DISABLE_SIGNUP=true`

**Safeguards:**
> :warning: Password strength indicator is visual feedback only — server-side validation (min 12 chars) is the actual gate. Do not rely on Alpine.js for security validation.

---

### TASK-11-09: Login Screen
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-02-01 (phx_gen_auth), TASK-11-01
**Description:**
LiveView at `/users/log_in`. Fields: email, password. "Forgot password?" link below form. OAuth buttons for GitHub and Google displayed if those providers are configured (check runtime config). On successful password verification: if TOTP enabled for user, redirect to `/users/totp` challenge. Otherwise, redirect to dashboard.

**Acceptance Criteria:**
- [ ] Login form renders with email and password fields
- [ ] "Forgot password?" link navigates to password reset form
- [ ] OAuth buttons only appear when providers are configured
- [ ] Successful login redirects to TOTP challenge (if enabled) or dashboard
- [ ] Failed login shows generic error ("Invalid email or password") without revealing which is wrong

**Safeguards:**
> :warning: Error messages must not reveal whether the email exists in the system. Always use a generic "Invalid email or password" message.

---

### TASK-11-10: Email Verification Screen
**Priority:** High
**Effort:** XS
**Depends on:** TASK-02-02 (Email verification flow)
**Description:**
Page at `/users/confirm/:token`. Shows pending verification state with a "Resend verification email" button. When user clicks the token link from their email, verifies the token and redirects to dashboard with a success flash. If token is invalid/expired, shows error with resend option.

**Acceptance Criteria:**
- [ ] Pending state renders with resend button
- [ ] Valid token click verifies user and redirects to dashboard
- [ ] Invalid/expired token shows error message with resend option
- [ ] Resend button sends new verification email

---

### TASK-11-11: TOTP Challenge Screen
**Priority:** High
**Effort:** S
**Depends on:** TASK-02-06 (TOTP login challenge)
**Description:**
LiveView at `/users/totp`. Shown after password verification when TOTP is enabled. Single 6-digit input field with auto-focus. Alpine.js auto-submits the form when 6 digits are entered (UI chrome — just triggers `phx-submit`). "Use recovery code instead" link switches to recovery code input. Error message on wrong code with retry.

**Acceptance Criteria:**
- [ ] 6-digit input auto-focuses on page load
- [ ] Form auto-submits when 6 digits entered (Alpine.js)
- [ ] Wrong code shows error, input clears for retry
- [ ] "Use recovery code instead" link switches to recovery code input mode
- [ ] Successful TOTP verification redirects to dashboard

**Safeguards:**
> :warning: The TOTP challenge page must only be accessible when the session is in a "pending 2FA" state. Direct navigation to `/users/totp` without a pending auth state should redirect to login.

---

### TASK-11-12: TOTP Setup Screen
**Priority:** High
**Effort:** S
**Depends on:** TASK-02-05 (TOTP setup flow)
**Description:**
LiveView at `/users/settings/totp/setup`. Requires authenticated session. Shows QR code (rendered as data URL image). Input field to confirm the TOTP code from authenticator app. On successful confirmation: TOTP enabled, recovery codes displayed (one-time). Download recovery codes as `.txt` file button. Copy all button (Alpine.js clipboard API).

**Acceptance Criteria:**
- [ ] QR code renders as data URL image
- [ ] Confirmation code input validates and enables TOTP
- [ ] Recovery codes displayed after TOTP setup (one-time display)
- [ ] Download as `.txt` button works
- [ ] Copy all button uses clipboard API (Alpine.js)

---

### TASK-11-13: Recovery Codes Screen
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-02-07 (Recovery codes)
**Description:**
LiveView at `/users/settings/totp/recovery_codes`. Shows current recovery codes (masked by default, reveal on click). "Regenerate codes" button with confirmation dialog (Alpine.js). "Copy all" button. Warning that regenerating invalidates old codes.

**Acceptance Criteria:**
- [ ] Recovery codes displayed (masked by default)
- [ ] Reveal codes on click
- [ ] Regenerate button with confirm dialog
- [ ] Copy all button works
- [ ] Warning message about regeneration invalidating old codes

---

### TASK-11-14: WebAuthn Screens
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-02-09 (WebAuthn registration)
**Description:**
LiveView at `/users/settings/webauthn`. Lists registered WebAuthn credentials (name, created_at, last used timestamp). "Add new credential" button triggers browser WebAuthn API via a LiveView JS hook (`KithWeb.Hooks.WebAuthn`). The hook calls the browser's `navigator.credentials.create()` API, sends the attestation back to the server via `pushEvent`. Remove credential button with confirmation.

**Acceptance Criteria:**
- [ ] Registered credentials listed with name, created_at, last used
- [ ] Add credential button triggers browser WebAuthn flow via JS hook
- [ ] Successful registration adds credential to list
- [ ] Remove button with confirmation removes credential
- [ ] User cannot remove last credential if it's their only login method

**Safeguards:**
> :warning: WebAuthn requires HTTPS. Development testing needs either localhost (which browsers exempt) or a self-signed cert setup.

---

### TASK-11-15: Password Reset Screens
**Priority:** High
**Effort:** XS
**Depends on:** TASK-02-03 (Password reset flow)
**Description:**
Two screens: (1) Forgot password form at `/users/reset_password` — email input, submit sends reset link, shows success message regardless of whether email exists. (2) Reset password form at `/users/reset_password/:token` — new password + confirmation, submit resets password and invalidates all sessions, redirects to login.

**Acceptance Criteria:**
- [ ] Forgot password form accepts email and shows success message
- [ ] Success message shown even if email doesn't exist (no enumeration)
- [ ] Reset form validates token, accepts new password
- [ ] Password reset invalidates all existing sessions
- [ ] After reset, user redirected to login page

---

### TASK-11-16: Dashboard
**Priority:** High
**Effort:** M
**Depends on:** TASK-11-05 (Navigation), TASK-11-04 (Components)
**Description:**
LiveView at `/` (root route, authenticated). Sections:
- **Recent contacts:** Last 5 modified contacts (avatar, name, last updated). Each links to contact profile.
- **Upcoming reminders count:** "X reminders in the next 30 days" with link to Upcoming Reminders page.
- **Activity feed:** Last 10 activities/calls/notes across all contacts, showing action type icon, contact name, timestamp. Uses `.relative_time` component.
- **Immich needs_review badge:** "X contacts need Immich review" banner, dismissable per session (Alpine.js `x-data`), links to `/contacts/immich_review`. Only shown if Immich enabled and count > 0.
- **Stats summary:** Total contacts count, total notes count.

**Acceptance Criteria:**
- [ ] Dashboard renders with all five sections
- [ ] Recent contacts shows last 5 modified (linked to profiles)
- [ ] Upcoming reminders count is accurate for 30-day window
- [ ] Activity feed shows last 10 items with relative timestamps
- [ ] Immich badge shows and is dismissable (hidden after dismiss until next session)
- [ ] Stats summary shows correct counts
- [ ] All sections render correctly in RTL layout

**Safeguards:**
> :warning: Dashboard queries must be efficient — avoid N+1. Use preloading and limit clauses. The dashboard is the most-visited page and must load fast.

---

### TASK-11-17: Contact List
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-11-04 (Components), TASK-11-06 (Policy)
**Description:**
LiveView at `/contacts`. Features:
- **Debounced live search:** `phx-change` on search input with 300ms debounce (use `phx-debounce="300"`). Searches name, email, phone. Updates list without page reload.
- **Sort controls:** Name A-Z, Name Z-A, Recently Added, Recently Contacted. Dropdown or toggle buttons.
- **Filter panel:** Tag checkboxes (multi-select), archived toggle, deceased toggle, favorite toggle. Filters applied cumulatively.
- **Pagination:** Cursor-based with "Load more" button at bottom. Default page size 20.
- **Each row:** Avatar (`.avatar`), display name, first 3 tags (`.tag_badge`), last talked to (`.relative_time`), favorite star button (`phx-click` toggle).
- **Bulk select:** Checkboxes on each row. When any selected, bulk action bar appears at top with: Assign tag, Remove tag, Archive, Delete. Selected count displayed.
- **Empty state:** "No contacts found" with "Add your first contact" button (`.empty_state` component).

**Acceptance Criteria:**
- [ ] Live search filters contacts with 300ms debounce, no page reload
- [ ] Sort controls change list ordering
- [ ] Tag filter, archived/deceased/favorite toggles work correctly
- [ ] Cursor pagination loads more contacts on button click
- [ ] Each row shows avatar, name, tags, last talked to, favorite star
- [ ] Bulk select shows action bar with correct operations
- [ ] Empty state shown when no contacts match
- [ ] Viewer role: bulk delete/archive buttons hidden
- [ ] RTL layout renders correctly

**Safeguards:**
> :warning: Debounce is critical — without it, every keystroke triggers a server round-trip. Use `phx-debounce="300"` on the search input. Do not implement custom debounce in JS.

**Notes:**
- Cursor pagination: track `after` cursor in socket assigns. "Load more" appends to existing list via `stream` or list concat.
- Search must be scoped to `account_id` at the context layer.

---

### TASK-11-18: Contact Profile
**Priority:** Critical
**Effort:** XL
**Depends on:** TASK-11-04, TASK-11-06, TASK-05-01 through TASK-05-11 (Sub-entities)
**Description:**
LiveView at `/contacts/:id`. Two-column layout:

**Sidebar (left in LTR, right in RTL):**
- Avatar (clickable to edit)
- Display name, nickname
- Gender + age (computed from birthdate)
- Birthdate (formatted via ex_cldr)
- Occupation / company
- Tags (with inline add/remove — small input + autocomplete)
- Favorite star toggle
- Last talked to (`.relative_time`)
- Deceased badge (if applicable)
- Archive status indicator
- Immich "View in Immich" button (if `immich_status: :linked`, opens external link)
- Actions: Edit contact, Archive/Unarchive, Delete (to trash), Merge

**Main content: Tab bar** with tabs: Life Events, Notes, Photos. Default tab from `current_user.default_profile_tab` preference. Each tab is a Level 2 LiveComponent that loads its own data:
- `KithWeb.Live.ContactProfile.NotesListComponent`
- `KithWeb.Live.ContactProfile.LifeEventsListComponent`
- `KithWeb.Live.ContactProfile.PhotosGalleryComponent`

Additional sidebar sections (below main info):
- Upcoming reminders for this contact

**Contact Profile sidebar sub-sections (required):**

**(a) Addresses section**
- List of contact addresses (city, country, street, etc.)
- Inline add form: fill fields → triggers geocoding (async, non-blocking) → saves
- Inline edit: click address → opens edit form inline
- Delete: removes address; if geocoords exist, they are cleared
- "Open in Maps" link for addresses with geocoordinates (links to OSM or Google Maps)
- Rendered as Level 3 function components for display; Level 2 LiveComponent for edit forms

**(b) Contact Fields section**
- List of contact fields (email, phone, social, etc.)
- Inline add form with type dropdown (populated from account's custom field types)
- Inline edit and delete
- Rendered as Level 3 function components for display; Level 2 LiveComponent for edit forms

**(c) Relationships section**
- List of relationships with type labels (e.g., "Friend of Jane Smith")
- Add form: relationship type dropdown + contact search autocomplete
- Delete relationship
- Links to related contact's profile
- Rendered as Level 3 function components for display; Level 2 LiveComponent for add/edit forms

**Acceptance Criteria:**
- [ ] Profile loads with sidebar and tabbed main content
- [ ] Default tab respects user preference
- [ ] Tab switching loads component data without full page reload
- [ ] Sidebar shows all contact metadata correctly
- [ ] Inline tag add/remove works
- [ ] Favorite toggle works instantly (optimistic UI update)
- [ ] "View in Immich" button appears only for linked contacts
- [ ] Edit/Archive/Delete actions work with appropriate policy checks
- [ ] Addresses, contact fields, relationships render in sidebar sections
- [ ] RTL layout: sidebar moves to right side, text right-aligned

**Safeguards:**
> :warning: Do NOT load all sub-entities on initial mount. Each tab LiveComponent loads its own data in `update/2`. This prevents slow initial page loads for contacts with many notes/events/photos.

**Notes:**
- Activities and Calls are displayed within the Life Events tab as a combined timeline, or as separate sub-sections. Follow the spec's tab structure: Life Events / Notes / Photos.
- The merge action button navigates to `/contacts/:id/merge`.

---

### TASK-11-19: Upcoming Reminders Page
**Priority:** High
**Effort:** M
**Depends on:** TASK-06-14 (Upcoming reminders query), TASK-11-04
**Description:**
LiveView at `/reminders`. Top-level nav item accessible to all roles. Features:
- **Window selector:** Tabs or dropdown for 30 / 60 / 90 days. Default 30 days. Changing window updates the list via `phx-click`.
- **Reminder list:** Grouped by date. Each row: contact avatar + name (link to profile), reminder type icon, reminder title, due date (`.date_display`), "Mark resolved" button, "Dismiss" button.
- **All roles can view.** Resolve/dismiss available to editors and admins.
- **Empty state:** Per window — "No reminders in the next X days."

**Acceptance Criteria:**
- [ ] Page renders with 30/60/90-day window selector
- [ ] Changing window updates reminder list
- [ ] Reminders grouped by date, sorted chronologically
- [ ] Each row shows contact info, type icon, title, due date
- [ ] Mark resolved and dismiss buttons work (create/update ReminderInstance)
- [ ] Viewer role can view but resolve/dismiss buttons are hidden
- [ ] Empty state shown per window when no reminders

**Safeguards:**
> :warning: The reminder query must be efficient — use the `upcoming/2` context function with proper indexing. Do not load all reminders and filter in Elixir.

---

### TASK-11-20: Settings Overview & Layout
**Priority:** High
**Effort:** S
**Depends on:** TASK-11-05, TASK-11-06
**Description:**
LiveView at `/settings` with a left sidebar listing settings sections. Each section is its own LiveView route. Sections:
- Profile (`/settings/profile`)
- Security (`/settings/security`)
- Account (`/settings/account`) — admin only
- Users & Invitations (`/settings/users`) — admin only
- Custom Data (`/settings/custom_data`) — admin for types, editor for tags
- Immich (`/settings/integrations/immich`)
- Export (`/settings/export`)
- Import (`/settings/import`)
- Audit Log (`/settings/audit_log`)

Admin-only sections hidden (not grayed) for non-admin users via `authorized?/3`.

**Acceptance Criteria:**
- [ ] Settings page renders with sidebar navigation
- [ ] Each section links to correct route
- [ ] Admin-only sections hidden for editor/viewer roles
- [ ] Active section highlighted in sidebar
- [ ] Settings layout works in RTL

---

### TASK-11-21: Settings — Profile
**Priority:** High
**Effort:** S
**Depends on:** TASK-08-01 (User settings context)
**Description:**
LiveView at `/settings/profile`. Form fields: display name format (dropdown), timezone (searchable dropdown), locale (dropdown from ex_cldr supported locales), currency (dropdown), temperature unit (Celsius/Fahrenheit), default profile tab (Life Events / Notes / Photos). "Me" contact linkage: search input to find and link a contact as yourself. Save button with success flash.

**Acceptance Criteria:**
- [ ] All user preference fields render and save correctly
- [ ] Timezone dropdown is searchable (Alpine.js combobox or LiveView search)
- [ ] Locale change takes effect on next page load
- [ ] "Me" contact linkage search and link works
- [ ] Form validates and shows errors inline

---

### TASK-11-22: Settings — Security
**Priority:** High
**Effort:** M
**Depends on:** TASK-02-17 through TASK-02-20 (Session/security tasks)
**Description:**
LiveView at `/settings/security`. Sections:
- **Active sessions:** List of current sessions (device/user-agent, IP address, last seen timestamp). "Revoke" button per session. "Log out all other devices" button.
- **TOTP status:** Enabled/disabled badge. If disabled: "Set up two-factor authentication" link to `/users/settings/totp/setup`. If enabled: "Manage recovery codes" link, "Disable 2FA" button (requires current TOTP code).
- **WebAuthn credentials:** List of registered credentials. "Add new" and "Remove" buttons. Links to `/users/settings/webauthn`.
- **Connected OAuth providers:** List of linked providers (GitHub, Google). Link/unlink buttons. Warning if unlinking would leave no login method.
- **Change password:** Current password, new password, confirm new password form.

**Acceptance Criteria:**
- [ ] Active sessions listed with device, IP, last seen
- [ ] Revoke individual session works
- [ ] Log out all other devices works
- [ ] TOTP status and management links correct
- [ ] WebAuthn credentials listed with add/remove
- [ ] OAuth providers listed with link/unlink
- [ ] Change password form validates and updates
- [ ] Cannot unlink last login method (error shown)

---

### TASK-11-23: Settings — Account (Admin Only)
**Priority:** High
**Effort:** M
**Depends on:** TASK-08-02 (Account settings context), TASK-11-06
**Description:**
LiveView at `/settings/account`. Admin only (mount checks policy, redirects to 403 for non-admin). Sections:
- Account name, timezone, send_hour (0-23 dropdown with note: "Changes take effect the following day").
- Custom genders CRUD list with drag-to-reorder.
- Feature modules toggles (checkboxes).
- Reminder rules: enable/disable 30-day and 7-day pre-notifications (checkboxes).
- Account data reset: requires typing account name to confirm. Shows warning.
- Account deletion: requires typing account name to confirm. Shows warning about permanent data loss.

**Acceptance Criteria:**
- [ ] Only admin users can access this page (403 for others)
- [ ] Account name, timezone, send_hour save correctly
- [ ] Custom genders CRUD with reorder works
- [ ] Feature module toggles save
- [ ] Reminder rules toggles save
- [ ] Data reset requires exact account name match to enable button
- [ ] Account deletion requires exact account name match to enable button
- [ ] Confirmation dialogs prevent accidental destructive actions

**Safeguards:**
> :warning: Data reset and account deletion are irreversible. The "type account name to confirm" pattern is mandatory — do not use a simple confirm dialog.

---

### TASK-11-24: Settings — Users & Invitations (Admin Only)
**Priority:** High
**Effort:** M
**Depends on:** TASK-08-06 (Invitation flow), TASK-08-07 (Role management)
**Description:**
LiveView at `/settings/users`. Admin only. Sections:
- **User list:** Table with name, email, role (dropdown to change), joined date, remove button. Cannot remove self. Cannot change own role.
- **Invite form:** Email input, role select (admin/editor/viewer), send invitation button.
- **Pending invitations:** List with email, role, sent date, status. Resend and revoke buttons.

**Acceptance Criteria:**
- [ ] User list shows all account members with role dropdown
- [ ] Role change via dropdown saves immediately
- [ ] Cannot remove self or change own role
- [ ] Invite form sends invitation email
- [ ] Pending invitations listed with resend/revoke actions
- [ ] Only admin can access (403 for others)

---

### TASK-11-25: Settings — Custom Data
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-08-03 through TASK-08-05, TASK-08-10
**Description:**
LiveView at `/settings/custom_data`. Sections:
- **Custom relationship types:** CRUD list with name (forward) and name_reverse_relationship (backward). Admin only.
- **Custom contact field types:** CRUD list with name and icon picker. Admin only.
- **Tags management:** List all tags with rename and delete actions. Merge two tags feature (select source and target, confirm). Editors can manage tags; admin for relationship/field types.

**Acceptance Criteria:**
- [ ] Relationship types CRUD works with forward/reverse names
- [ ] Contact field types CRUD works with icon selection
- [ ] Tags list with rename, delete, merge functionality
- [ ] Cannot delete relationship/field types in use (error shown)
- [ ] Permission levels enforced (admin for types, editor for tags)

---

### TASK-11-26: Settings — Immich
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-08-13 (Immich settings context)
**Description:**
LiveView at `/settings/integrations/immich`. Features:
- Enable/disable toggle
- Base URL input field
- API key input field (masked, with reveal toggle)
- "Test connection" button — calls `Kith.Immich.Client.list_people/2` and shows success/failure result
- Status indicator: ok (green) / error (red) / disabled (gray)
- Last sync time and next sync time display
- Consecutive failures count (if in error state)
- "Sync Now" button (triggers immediate sync)
- "Disconnect" button (clears config, sets status to disabled)
- Error log if in error state

**Acceptance Criteria:**
- [ ] Enable/disable toggle works
- [ ] URL and API key inputs save correctly
- [ ] Test connection button shows success or failure
- [ ] Status indicator reflects current state
- [ ] Sync times display correctly
- [ ] Sync Now button triggers ImmichSyncWorker
- [ ] Disconnect clears all Immich configuration
- [ ] Error state shows failure count and error details

---

### TASK-11-27: Settings — Export
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-09-01 through TASK-09-03 (Export tasks)
**Description:**
LiveView at `/settings/export`. Two sections:
- **vCard export:** "Download all contacts as .vcf" button. Triggers download of all contacts as vCard file.
- **JSON export:** "Export all data as JSON" button. For large accounts (> 500 contacts), show message: "We'll email you when your export is ready." Triggers Oban job, sends email with download link when complete.

**Acceptance Criteria:**
- [ ] vCard download button triggers file download
- [ ] JSON export button works for small accounts (immediate download)
- [ ] Large account JSON export shows email notification message
- [ ] Export respects account scoping

---

### TASK-11-28: Settings — Import
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-09-04, TASK-09-05 (Import tasks)
**Description:**
LiveView at `/settings/import`. File upload for `.vcf` files. Upload area (drag-and-drop via Alpine.js + `Phoenix.LiveView.Upload`). Progress indicator during processing. Results summary: "X contacts imported. Y skipped (parse errors)." Error list if any. Warning banner: "Import creates new contacts. Existing contacts are not updated. Review for duplicates after import."

**Acceptance Criteria:**
- [ ] File upload accepts .vcf files
- [ ] Progress indicator shows during import processing
- [ ] Results summary shows imported and skipped counts
- [ ] Error details listed if any contacts failed to parse
- [ ] Warning banner displayed prominently before import

---

### TASK-11-29: Settings — Audit Log
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-12-01 (Audit log context — if in Phase 12)
**Description:**
LiveView at `/settings/audit_log`. Filterable table with columns: timestamp, user name, event type, contact name (link to contact if still exists), metadata preview. Filters: date range (start/end date pickers), event type (dropdown), contact name (search), user (dropdown). Cursor-based pagination with "Load more" button.

**Acceptance Criteria:**
- [ ] Audit log table renders with all columns
- [ ] Date range filter works
- [ ] Event type filter works
- [ ] Contact name search filter works
- [ ] User filter works
- [ ] Pagination loads more entries
- [ ] Contact name links to profile (if contact exists) or shows plain text (if deleted)
- [ ] Admin only access enforced

---

### TASK-11-30: Immich Review Screen
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-07-15 (Immich review data layer), TASK-11-04
**Description:**
LiveView at `/contacts/immich_review`. Lists contacts with `immich_status: :needs_review`. Each card shows:
- Contact name and avatar
- Candidate list: each candidate shows Immich thumbnail (loaded from Immich URL), Immich person name, Confirm button, Reject button
- For contacts with multiple candidates, all are listed

Batch mode: "Select all" checkbox at top. When contacts selected, batch Confirm/Reject buttons appear. Empty state: "All Immich links reviewed!" with link back to dashboard.

**Acceptance Criteria:**
- [ ] Lists all contacts needing Immich review
- [ ] Each candidate shows thumbnail, name, confirm/reject buttons
- [ ] Confirm sets `immich_status: :linked`, stores person ID and URL
- [ ] Reject removes candidate from list; if no candidates left, sets `:unlinked`
- [ ] Batch select all + batch confirm/reject works
- [ ] Empty state shown when no contacts need review
- [ ] After confirming, "View in Immich" button appears on contact profile

**Safeguards:**
> :warning: Immich thumbnails are loaded from external URLs. Ensure CSP allows image loading from the configured `IMMICH_BASE_URL`. Add it to `img-src` directive dynamically based on account Immich config.

---

### TASK-11-31: Contact Merge Screen
**Priority:** Medium
**Effort:** L
**Depends on:** TASK-09-06, TASK-09-07 (Merge flow)
**Description:**
LiveView at `/contacts/:id/merge`. Multi-step wizard:

**Step 1 — Select merge target:** Search input to find and select the contact to merge with. Shows search results as contact cards. Selecting a contact advances to step 2.

**Step 2 — Survivor selection:** Radio buttons: "Keep [Contact A]'s identity fields" or "Keep [Contact B]'s identity fields". Shows side-by-side comparison of identity fields (name, birthdate, occupation, etc.).

**Step 3 — Dry-run preview:** Table showing what will be merged: notes count, activities count, calls count, life events count, photos count, documents count, addresses, contact fields, relationships. Explicitly lists relationships that will be deduplicated (same type + same third contact). Shows "X relationships will be removed as duplicates."

**Step 4 — Confirm:** "Confirm Merge" button. On click: executes merge transaction, redirects to survivor's profile with success flash.

**Acceptance Criteria:**
- [ ] Step 1: contact search works and selects merge target
- [ ] Step 2: survivor selection with side-by-side comparison
- [ ] Step 3: dry-run preview shows accurate counts and relationship dedup list
- [ ] Step 4: confirm executes merge and redirects to survivor profile
- [ ] Non-survivor is soft-deleted (appears in trash)
- [ ] Editor and admin can merge; viewer cannot
- [ ] Back button works at each step

**Safeguards:**
> :warning: The dry-run preview must accurately reflect what the merge will do. Run the same logic as the actual merge but in a read-only query. Do not show stale data.

---

### TASK-11-32: Trash View
**Priority:** High
**Effort:** S
**Depends on:** TASK-04-09 (Trash view), TASK-11-06
**Description:**
LiveView at `/contacts/trash`. Lists all soft-deleted contacts for the account. Each row shows:
- Contact name and avatar
- Deleted date (`.date_display`)
- Days until permanent deletion: "Will be permanently deleted in X days" with visual progress indicator
- Admin: "Restore" button (sets `deleted_at = NULL`)
- "Permanently delete" button with confirmation dialog (hard-deletes immediately)

Empty state: "Trash is empty."

**Acceptance Criteria:**
- [ ] Lists soft-deleted contacts with deletion date and countdown
- [ ] Restore button works (admin only, hidden for others)
- [ ] Permanent delete button with confirmation works
- [ ] Countdown accurately shows days remaining (30 - days since deletion)
- [ ] Empty state shown when trash is empty
- [ ] Viewer cannot see restore or permanent delete buttons

**Safeguards:**
> :warning: Permanent delete is irreversible. The confirmation dialog must require explicit action (not just a browser `confirm()`). Use a modal with a "Type DELETE to confirm" pattern.

---

### TASK-11-NEW-A: Contact Create LiveView (`/contacts/new`)
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-11-06 (Policy), TASK-11-04 (Components), TASK-04-NEW-A (Dynamic contact fields)
**Description:**
Full-page LiveView for creating a new contact.

**Route:** `GET /contacts/new` (full-page LiveView, not a modal)

**Fields:**
- First name (required), last name (optional), nickname (optional)
- Birthdate (date picker, optional)
- Gender (dropdown from account's custom genders, optional)
- Company (optional), occupation (optional)
- Deceased toggle (boolean)
- Favorite toggle (boolean)
- Avatar upload (`live_file_input`, optional)
- Dynamic contact field rows (email/phone/social — uses custom field types from TASK-04-NEW-A)

**Behavior:**
- On successful save: redirect to contact profile (`/contacts/:id`)
- On validation error: re-render form with inline field-level errors
- Avatar upload: uses Phoenix LiveView upload; preview shown before save

**Policy:**
- Editor/admin: full access
- Viewer: redirect to contacts list with flash "You don't have permission to create contacts"

**Acceptance Criteria:**
- [ ] `/contacts/new` renders the full create form
- [ ] All listed fields are present
- [ ] Dynamic contact field rows work (add/remove before save)
- [ ] Avatar preview shown after file selection
- [ ] Successful save redirects to new contact's profile
- [ ] Validation errors shown inline (not just flash)
- [ ] Viewer is redirected with an error flash
- [ ] Tests: create success, validation failure, viewer redirect

---

### TASK-11-NEW-B: Contact Edit LiveView (`/contacts/:id/edit`)
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-11-NEW-A (Contact Create — shares field set), TASK-11-06 (Policy)
**Description:**
Full-page LiveView for editing an existing contact.

**Route:** `GET /contacts/:id/edit` (separate route, NOT an inline LiveComponent on the profile page)

**Rationale:** Edit is a separate route to keep the contact profile page complexity manageable. The profile page shows data; the edit route allows mutation.

**Fields:** Same complete field set as TASK-11-NEW-A (Contact Create), pre-populated with existing values.

**Contact field management:** Existing contact fields pre-populated; add/remove works same as create; existing fields marked `_delete: true` when removed, deleted on save.

**Behavior:**
- On successful save: redirect back to contact profile (`/contacts/:id`)
- On validation error: re-render with inline errors
- Avatar: shows current avatar thumbnail; allows replacement or removal

**Policy:**
- Editor/admin: full access
- Viewer: redirect to contact profile with flash "You don't have permission to edit contacts"

**Acceptance Criteria:**
- [ ] `/contacts/:id/edit` renders pre-populated form
- [ ] All fields pre-populated correctly
- [ ] Existing contact fields shown and editable
- [ ] Avatar replacement/removal works
- [ ] Successful save redirects to profile
- [ ] Viewer redirected with error flash
- [ ] Tests: edit success, field update, viewer redirect

---

### TASK-11-NEW-C: Invitation Acceptance LiveView (`/invitations/:token`)
**Priority:** High
**Effort:** S
**Depends on:** TASK-08-06 (Invitation flow — Phase 08)
**Description:**
Unauthenticated LiveView for accepting a team invitation.

**Route:** `GET /invitations/:token` — in the router's `:browser` pipeline (NOT behind `:require_authenticated_user`)

**UI:**
- Shows inviting account name and invited email address
- Password creation form: "Create your password", "Confirm password"
- Submit button: "Accept invitation and join [account name]"

**Behavior:**
1. On mount: look up invitation by token; if expired or already used → show error ("This invitation has expired or has already been used")
2. On submit: call `Accounts.accept_invitation/2` (Phase 08)
3. On success: log the user in, redirect to dashboard with flash "Welcome to [account name]!"
4. On validation error: show inline password errors

**Policy:** No authentication required — works without an existing session

**Acceptance Criteria:**
- [ ] `/invitations/:token` renders without an authenticated session
- [ ] Expired/invalid token shows error state (not a crash)
- [ ] Form shows inviting account name
- [ ] Successful submission creates user, logs them in, redirects to dashboard
- [ ] Invalid token is not confused with a server error (renders gracefully)
- [ ] Tests: valid token → success; expired token → error state; wrong password confirmation → validation error

---

## E2E Product Tests

### TEST-11-01: Dashboard Loads Correctly
**Type:** Browser (Playwright)
**Covers:** TASK-11-16

**Scenario:**
Verify that the dashboard renders all expected sections when a logged-in user navigates to the root page.

**Steps:**
1. Log in as an editor user with an account that has contacts, reminders, and recent activity.
2. Navigate to `/` (dashboard).
3. Verify that the "Recent Contacts" section shows up to 5 contacts.
4. Verify that the "Upcoming Reminders" section shows a count with a link to the reminders page.
5. Verify that the "Activity Feed" section shows recent activities with timestamps.
6. Verify that the stats summary shows total contacts and total notes counts.

**Expected Outcome:**
Dashboard renders with all five sections populated with correct data. No loading errors.

---

### TEST-11-02: Contact List Search Updates Without Page Reload
**Type:** Browser (Playwright)
**Covers:** TASK-11-17

**Scenario:**
Verify that typing in the search box on the contact list page updates the displayed contacts without a full page reload.

**Steps:**
1. Log in and navigate to `/contacts`.
2. Verify the full contact list is displayed.
3. Type a partial contact name into the search input.
4. Wait 300ms for debounce.
5. Verify the list updates to show only matching contacts.
6. Verify no full page reload occurred (check that the browser URL did not change and the page DOM was not fully replaced).

**Expected Outcome:**
Contact list filters to show only contacts matching the search term. The update happens via LiveView DOM patch, not a full page reload.

---

### TEST-11-03: Contact List Tag Filter
**Type:** Browser (Playwright)
**Covers:** TASK-11-17

**Scenario:**
Verify that applying a tag filter on the contact list shows only contacts with that tag.

**Steps:**
1. Log in and navigate to `/contacts`.
2. Open the filter panel.
3. Select a specific tag checkbox.
4. Verify the contact list updates to show only contacts with that tag.
5. Deselect the tag.
6. Verify the full list is restored.

**Expected Outcome:**
Only contacts with the selected tag are displayed when the filter is active. Deselecting restores the full list.

---

### TEST-11-04: Contact List Bulk Archive
**Type:** Browser (Playwright)
**Covers:** TASK-11-17

**Scenario:**
Verify that selecting multiple contacts and using the bulk archive action archives all selected contacts.

**Steps:**
1. Log in as an editor and navigate to `/contacts`.
2. Select 3 contacts using their checkboxes.
3. Verify the bulk action bar appears showing "3 selected".
4. Click "Archive" in the bulk action bar.
5. Confirm the archive action.
6. Verify the 3 contacts disappear from the default list.
7. Toggle the "Show archived" filter.
8. Verify the 3 contacts appear in the filtered list.

**Expected Outcome:**
Selected contacts are archived and removed from the default view. They appear when the archived filter is toggled on.

---

### TEST-11-05: Create Contact With All Fields
**Type:** Browser (Playwright)
**Covers:** TASK-11-17, TASK-04-02

**Scenario:**
Verify that creating a contact with all fields works and the profile displays them correctly.

**Steps:**
1. Log in as an editor and navigate to `/contacts`.
2. Click "Add contact" button.
3. Fill in: first name, last name, nickname, gender, birthdate, description, occupation, company.
4. Submit the form.
5. Verify redirect to the new contact's profile page.
6. Verify all entered fields are visible in the sidebar.

**Expected Outcome:**
Contact is created and profile page shows all entered fields. A birthday reminder is auto-created if birthdate was set.

---

### TEST-11-06: Contact Profile Tab Switching
**Type:** Browser (Playwright)
**Covers:** TASK-11-18

**Scenario:**
Verify that switching tabs on the contact profile page loads the correct tab content without a full page reload.

**Steps:**
1. Log in and navigate to a contact's profile page.
2. Verify the default tab content is loaded.
3. Click the "Notes" tab.
4. Verify the Notes tab content loads (notes list or empty state).
5. Click the "Photos" tab.
6. Verify the Photos tab content loads (photo gallery or empty state).
7. Verify no full page reload occurred during tab switches.

**Expected Outcome:**
Each tab loads its respective content via LiveComponent update. No full page reload. Previously loaded tab content is not visible when another tab is active.

---

### TEST-11-07: Add Note From Contact Profile
**Type:** Browser (Playwright)
**Covers:** TASK-11-18, TASK-05-01

**Scenario:**
Verify that adding a note from the contact profile page shows it in the notes list.

**Steps:**
1. Log in and navigate to a contact's profile page.
2. Click the "Notes" tab.
3. Click "Add note" button.
4. Type note content in the Trix editor.
5. Submit the note form.
6. Verify the new note appears in the notes list with correct content and timestamp.

**Expected Outcome:**
Note is created and immediately visible in the notes list with the entered content and a "just now" timestamp.

---

### TEST-11-08: Upload Photo to Contact
**Type:** Browser (Playwright)
**Covers:** TASK-11-18, TASK-05-04

**Scenario:**
Verify that uploading a photo to a contact displays it in the photo gallery.

**Steps:**
1. Log in and navigate to a contact's profile page.
2. Click the "Photos" tab.
3. Click "Upload photo" or use drag-and-drop.
4. Select a valid image file.
5. Wait for upload to complete.
6. Verify the photo appears in the gallery.

**Expected Outcome:**
Photo is uploaded and immediately visible in the contact's photo gallery.

---

### TEST-11-09: Edit Contact Name Updates Immediately
**Type:** Browser (Playwright)
**Covers:** TASK-11-18

**Scenario:**
Verify that editing a contact's name updates the sidebar display immediately.

**Steps:**
1. Log in and navigate to a contact's profile page.
2. Click "Edit contact" button.
3. Change the first name to a new value.
4. Save the form.
5. Verify the sidebar immediately shows the updated name.
6. Verify a success flash message appears.

**Expected Outcome:**
Contact name updates in the sidebar after save. Flash message confirms the update.

---

### TEST-11-10: Archive Contact Moves to Trash
**Type:** Browser (Playwright)
**Covers:** TASK-11-18, TASK-11-32

**Scenario:**
Verify that archiving a contact removes it from the default list and soft-deleting shows it in trash with a countdown.

**Steps:**
1. Log in as an editor and navigate to a contact's profile.
2. Click "Delete" (soft-delete to trash).
3. Confirm the deletion.
4. Navigate to `/contacts` — verify the contact is no longer in the list.
5. Navigate to `/contacts/trash` — verify the contact appears with a deletion countdown.

**Expected Outcome:**
Contact disappears from the main list and appears in trash with "Will be permanently deleted in 30 days" message.

---

### TEST-11-11: Admin Restores Contact From Trash
**Type:** Browser (Playwright)
**Covers:** TASK-11-32

**Scenario:**
Verify that an admin can restore a soft-deleted contact from the trash.

**Steps:**
1. Log in as an admin.
2. Navigate to `/contacts/trash`.
3. Find a soft-deleted contact.
4. Click "Restore" button.
5. Verify the contact disappears from trash.
6. Navigate to `/contacts` — verify the contact is back in the list with `deleted_at` cleared.

**Expected Outcome:**
Contact is restored to the main list. It no longer appears in trash. `deleted_at` is set to null.

---

### TEST-11-12: Settings Timezone Update
**Type:** Browser (Playwright)
**Covers:** TASK-11-21

**Scenario:**
Verify that updating the timezone in settings persists and affects date display.

**Steps:**
1. Log in and navigate to `/settings/profile`.
2. Change timezone to a different value (e.g., "America/New_York" to "Asia/Tokyo").
3. Save the form.
4. Verify success flash message.
5. Reload the page and verify the timezone dropdown shows the updated value.

**Expected Outcome:**
Timezone change persists across page reloads. Dates on subsequent pages are displayed in the new timezone.

---

### TEST-11-13: Settings Invite User
**Type:** Browser (Playwright)
**Covers:** TASK-11-24

**Scenario:**
Verify that an admin can invite a new user and the invitation appears in the pending list.

**Steps:**
1. Log in as an admin and navigate to `/settings/users`.
2. Enter an email address in the invite form.
3. Select "editor" role.
4. Click "Send invitation".
5. Verify the invitation appears in the pending invitations list with correct email and role.

**Expected Outcome:**
Invitation is created and visible in the pending list. An invitation email is sent (verify in Mailpit in dev).

---

### TEST-11-14: Settings Accept Invitation (Separate Session)
**Type:** Browser (Playwright)
**Covers:** TASK-11-24

**Scenario:**
Verify that a new user can accept an invitation and log in.

**Steps:**
1. Admin sends invitation (from TEST-11-13).
2. In a separate browser context (incognito/new session), navigate to the invitation acceptance URL from the email.
3. Fill in password and create account.
4. Verify redirect to dashboard.
5. Verify the new user appears in the admin's user list with the correct role.

**Expected Outcome:**
New user successfully creates account via invitation, can log in, and appears in the user management list with the assigned role.

---

### TEST-11-15: TOTP Setup Complete Flow
**Type:** Browser (Playwright)
**Covers:** TASK-11-12

**Scenario:**
Verify the complete TOTP setup flow including recovery code display.

**Steps:**
1. Log in and navigate to `/users/settings/totp/setup`.
2. Verify QR code image is displayed.
3. Enter a valid TOTP code (use a TOTP library in the test to generate from the displayed secret).
4. Submit the confirmation form.
5. Verify TOTP is now enabled.
6. Verify recovery codes are displayed.
7. Verify "Copy all" button copies codes to clipboard.

**Expected Outcome:**
TOTP is enabled after code confirmation. Recovery codes are displayed one time. Subsequent visits to security settings show TOTP as enabled.

---

### TEST-11-16: Contact Merge Dry-Run and Execution
**Type:** Browser (Playwright)
**Covers:** TASK-11-31

**Scenario:**
Verify the contact merge flow including dry-run preview and execution.

**Steps:**
1. Log in as an editor with two contacts that have some overlapping relationships.
2. Navigate to first contact's profile.
3. Click "Merge with another contact".
4. Search for and select the second contact.
5. Choose which contact's identity to keep (survivor).
6. Verify the dry-run preview shows correct merge summary (sub-entity counts, relationship dedup list).
7. Click "Confirm Merge".
8. Verify redirect to survivor's profile.
9. Verify the non-survivor contact is in the trash.

**Expected Outcome:**
Merge completes successfully. Survivor profile has all sub-entities from both contacts. Non-survivor is soft-deleted.

---

### TEST-11-17: Immich Review Confirm Link
**Type:** Browser (Playwright)
**Covers:** TASK-11-30

**Scenario:**
Verify that confirming an Immich link from the review screen updates the contact profile.

**Steps:**
1. Set up: ensure a contact has `immich_status: :needs_review` with a candidate.
2. Log in and navigate to `/contacts/immich_review`.
3. Find the contact and click "Confirm" next to the candidate.
4. Navigate to the contact's profile page.
5. Verify the "View in Immich" button is present and links to the correct Immich URL.

**Expected Outcome:**
After confirming the Immich link, the contact profile shows "View in Immich" button pointing to the Immich person page.

---

### TEST-11-18: RTL Layout Verification
**Type:** Browser (Playwright)
**Covers:** TASK-11-01, TASK-11-03

**Scenario:**
Verify that switching to an RTL locale (Arabic) correctly mirrors the layout.

**Steps:**
1. Log in and change locale to Arabic (`ar`) in settings.
2. Navigate to the dashboard.
3. Verify `<html dir="rtl" lang="ar">` is set.
4. Verify the sidebar is on the right side of the screen.
5. Verify text is right-aligned.
6. Navigate to the contact list page.
7. Verify the search input and filter panel are mirrored.
8. Navigate to a contact profile.
9. Verify the sidebar is on the right, main content on the left.

**Expected Outcome:**
All pages render correctly in RTL mode. Sidebar on right, text right-aligned, Tailwind logical properties ensure proper mirroring of all spacing and positioning.

---

### TEST-11-19: Upcoming Reminders Window Change
**Type:** Browser (Playwright)
**Covers:** TASK-11-19

**Scenario:**
Verify that changing the reminder window from 30 to 90 days updates the displayed reminders.

**Steps:**
1. Set up: create reminders with due dates at 15 days, 45 days, and 75 days from now.
2. Log in and navigate to `/reminders`.
3. With 30-day window selected, verify only the 15-day reminder is shown.
4. Switch to 60-day window.
5. Verify the 15-day and 45-day reminders are shown.
6. Switch to 90-day window.
7. Verify all three reminders are shown.

**Expected Outcome:**
Reminder list updates to include more reminders as the window increases. Each window shows only reminders within its date range.

---

### TEST-11-20: Viewer Role 403 on Edit Contact
**Type:** Browser (Playwright)
**Covers:** TASK-11-06, TASK-11-07

**Scenario:**
Verify that a viewer role user is shown a 403 page when trying to navigate directly to an edit contact URL.

**Steps:**
1. Log in as a viewer role user.
2. Navigate directly to `/contacts/:id/edit` (using a valid contact ID).
3. Verify the 403 error page is shown.
4. Verify the 403 page explains the role limitation.
5. Verify the 403 page has a link to the home page.

**Expected Outcome:**
Viewer user sees a 403 page with an explanation that their role does not have permission to edit contacts. A link to the home page is provided.

---

## Phase Safeguards

- **RTL from day one:** Every template must use Tailwind logical properties. Do not defer RTL support — it is dramatically harder to retrofit than to build correctly from the start.
- **No Alpine.js state mutations:** Alpine.js must never read from or write to server state. This boundary is a coding standard enforced in code review. If a feature requires server state interaction, it must go through LiveView events.
- **Policy checks at two layers:** Template-level hiding (via `authorized?/3`) is for UX only. The context layer and LiveView `mount/3` must also enforce authorization. A missing template check is a UX bug; a missing context check is a security bug.
- **No N+1 on dashboard and list pages:** Use Ecto preloading, join queries, or aggregate subqueries. The dashboard and contact list are the most visited pages and must be performant.
- **Tab content lazy loading:** Contact profile tabs (Notes, Life Events, Photos) must load their data only when the tab is selected. Do not preload all sub-entities on initial profile mount.

## Phase Notes

- The `docs/frontend-conventions.md` document (TASK-11-02) is a Phase 00 pre-code gate. The implementation of the document belongs here in Phase 11, but it must be written and reviewed before the first contact profile LiveView is merged.
- Contact profile is the most complex screen (TASK-11-18) and should be broken into sub-tasks during implementation: sidebar, tab system, each tab component.
- The Trix editor hook for notes (referenced in TASK-11-18 via Phase 05) requires a LiveView JS hook that syncs Trix content to a hidden form input. This is a critical integration point between the JS ecosystem and LiveView.
- All settings pages follow the same pattern: LiveView at a specific route, form with `phx-submit`, flash message on success. Consider extracting a shared settings form component pattern.

---

## Implementation Decisions

### Decision A: CSP Nonce Strategy
Per-request nonce generated in `KithWeb.Plugs.CSP` using `Base.encode64(:crypto.strong_rand_bytes(16))`. Replaced `'unsafe-inline'` in `script-src` with `'nonce-#{nonce}'`. Nonce assigned to conn and referenced in root layout via `nonce={assigns[:csp_nonce]}`.

### Decision B: RTL Detection
`@rtl_locales ~w(ar he fa ur)` — base locale extracted by splitting on `-` and downcasing. Returns `"rtl"` or `"ltr"`. Implemented in `KithWeb.Plugs.AssignLocale`.

### Decision C: Sidebar Collapse Persistence
Desktop sidebar collapse state stored in `localStorage` via Alpine.js `x-init`/`x-effect`. No server round-trip for UI chrome state — follows Alpine.js scope boundary rule.

### Decision D: Current Path Tracking
`assign_current_path/1` in `UserAuth` uses `attach_hook(:set_current_path, :handle_params, ...)` to parse URI path on every navigation. Powers active-state highlighting in sidebar and mobile nav.

### Decision E: Component Organization
11 function components in `KithWeb.KithComponents` (Level 3): `avatar`, `contact_badge`, `tag_badge`, `reminder_row`, `card`, `section_header`, `empty_state`, `role_badge`, `emotion_badge`, `date_display`, `relative_time`. All globally imported via `html_helpers/0`.

### Decision F: Avatar Deterministic Colors
Avatar background color derived from `name |> :erlang.phash2(8)` mapping to 8 Tailwind color classes. Ensures same contact always gets same color across sessions.

### Decision G: Error Pages Standalone
Custom 404/403/500 pages are standalone HTML (no layout dependency) so they render even when the app shell is broken. 500 includes a unique reference ID via `System.unique_integer/1`.

### Decision H: Dashboard Query Placement
All dashboard data loaded in `handle_params/3`, not `mount/3` (Phoenix Iron Law). Added `recent_contacts/2`, `contact_count/1`, `note_count/1`, `recent_activity/2` to `Kith.Contacts`.

### Decision I: Contact Profile Tab Simplification
Reduced from 9 tabs to 3 main content tabs (Notes, Life Events, Photos). Addresses, contact fields, relationships, and reminders moved to sidebar sections for always-visible access.

### Decision J: Cursor-Based Pagination
Contact list uses cursor pagination with last contact ID as cursor. `list_contacts_paginated/2` fetches `limit+1` to detect `has_more`. All filtering (search, archived, deceased, favorites, tags) done at DB level.

### Decision K: Settings Sidebar Navigation
Shared `SettingsLayout.settings_shell/1` component with nav items that highlight based on `@current_path` match. Policy-gated items (Account, Integrations) hidden for non-admin users.

### Decision L: Invitation Acceptance Route
`/invitations/:token` placed in public `current_user` live_session (not authenticated scope). Uses `Accounts.get_invitation_by_token/1` to validate, then `Accounts.accept_invitation/2` to create user and accept.

### Decision M: Registration Password Strength
Alpine.js `x-data` scope with `pw` variable drives a visual strength meter bar. Purely client-side UI feedback — does not replace server-side validation. Follows Alpine scope boundary (no server state mutation).
