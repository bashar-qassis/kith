# Smoke Test Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all issues found during Playwright smoke testing: CSP/Alpine.js errors, post-registration redirect, API controller bugs, unqualified module references, missing vendor download automation, and cleanup warnings. Add Playwright smoke tests permanently.

**Architecture:** Six independent fix areas: (1) Switch Alpine.js to CSP build with `Alpine.data()` components, (2) Fix `signed_in_path` for LiveView sockets, (3) Correct all API field names and function references, (4) Add aliases for cross-context Ecto queries, (5) Add `mix assets.vendor` task, (6) Commit Playwright e2e tests. Each area can be worked in parallel as they touch different files.

**Tech Stack:** Elixir/Phoenix 1.8, Alpine.js 3.14 (`@alpinejs/csp`), Playwright, Ecto, Tailwind v4

---

## File Map

| Area | File | Action |
|------|------|--------|
| Alpine CSP | `assets/package.json` | Modify: swap `alpinejs` for `@alpinejs/csp` |
| Alpine CSP | `assets/js/app.js` | Modify: import CSP build, register `Alpine.data()` components |
| Alpine CSP | `assets/js/alpine/sidebar.js` | Create: sidebar + user menu component |
| Alpine CSP | `assets/js/alpine/password_strength.js` | Create: password strength meter component |
| Alpine CSP | `assets/js/alpine/totp_challenge.js` | Create: TOTP/recovery toggle component |
| Alpine CSP | `assets/js/alpine/recovery_codes.js` | Create: recovery code copy/download component |
| Alpine CSP | `assets/js/alpine/lightbox.js` | Create: photo lightbox component |
| Alpine CSP | `assets/js/alpine/dismissible.js` | Create: dismissible banner component |
| Alpine CSP | `lib/kith_web/components/layouts.ex` | Modify: replace inline Alpine with component refs |
| Alpine CSP | `lib/kith_web/live/user_live/registration.ex` | Modify: replace inline Alpine with component ref |
| Alpine CSP | `lib/kith_web/live/user_live/totp_challenge.ex` | Modify: replace inline Alpine with component ref |
| Alpine CSP | `lib/kith_web/live/user_live/totp_setup.ex` | Modify: replace inline Alpine with component ref |
| Alpine CSP | `lib/kith_web/live/dashboard_live/index.ex` | Modify: replace inline Alpine with component ref |
| Alpine CSP | `lib/kith_web/live/contact_live/photos_gallery_component.ex` | Modify: replace inline Alpine with component ref |
| Auth | `lib/kith_web/user_auth.ex:303-307` | Modify: handle LiveView socket in `signed_in_path/1` |
| Auth | `lib/kith_web/controllers/user_session_controller.ex:9-15` | Modify: use "Welcome!" for new registrations |
| API | `lib/kith_web/controllers/api/contact_json.ex:118,177,179,188` | Modify: fix field names |
| API | `lib/kith_web/controllers/api/photo_controller.ex:45,95` | Modify: `filename` -> `file_name` (create + json) |
| API | `lib/kith_web/controllers/api/document_controller.ex:43,45,91-99` | Modify: `filename` -> `file_name`, `size_bytes` -> `file_size` (create + json) |
| API | `lib/kith_web/controllers/api/note_controller.ex:132,155` | Modify: `is_favorite` -> `favorite` |
| API | `lib/kith_web/controllers/api/relationship_type_controller.ex:86` | Modify: `name_reverse_relationship` -> `reverse_name` |
| API | `lib/kith_web/controllers/api/tag_controller.ex:91,110,130,153` | Modify: `assign_tag` -> `tag_contact`, `remove_tag` -> `untag_contact` |
| API | `lib/kith_web/controllers/api/call_controller.ex:55` | Modify: `create_call/3` -> `create_call/2` |
| API | `lib/kith_web/controllers/api/address_controller.ex:43` | Modify: `create_address/3` -> `create_address/2` |
| API | `lib/kith_web/controllers/api/me_controller.ex:33` | Modify: stub `update_user_settings` |
| Timezone | `lib/kith/accounts/account.ex:51-63` | Modify: replace `Tzdata` with `Tz.TimeZoneDatabase` |
| Timezone | `lib/kith/accounts/user.ex:165-177` | Modify: replace `Tzdata` with `Tz.TimeZoneDatabase` |
| Cross-ctx | `lib/kith/contacts.ex:11-29,1612,1638` | Modify: add aliases, fix `created_at` -> `inserted_at`, `called_at` -> `occurred_at` |
| Vendor | `lib/mix/tasks/assets_vendor.ex` | Create: Mix task for downloading vendor JS |
| Vendor | `mix.exs:142` | Modify: hook `assets.vendor` into `setup` alias |
| Warnings | Various API controllers | Modify: prefix unused vars with `_` |
| Playwright | `playwright.config.ts` | Already created -- keep |
| Playwright | `e2e/smoke.spec.ts` | Already created -- update for fixed behavior |
| Playwright | `.gitignore` | Modify: add Playwright artifacts |
| Playwright | `package.json` | Already created -- keep |

---

## Task 1: Switch Alpine.js to CSP Build

**Files:**
- Modify: `assets/package.json`
- Modify: `assets/js/app.js`
- Create: `assets/js/alpine/sidebar.js`
- Create: `assets/js/alpine/password_strength.js`
- Create: `assets/js/alpine/totp_challenge.js`
- Create: `assets/js/alpine/recovery_codes.js`
- Create: `assets/js/alpine/lightbox.js`
- Create: `assets/js/alpine/dismissible.js`
- Modify: `lib/kith_web/components/layouts.ex`
- Modify: `lib/kith_web/live/user_live/registration.ex`
- Modify: `lib/kith_web/live/user_live/totp_challenge.ex`
- Modify: `lib/kith_web/live/user_live/totp_setup.ex`
- Modify: `lib/kith_web/live/dashboard_live/index.ex`
- Modify: `lib/kith_web/live/contact_live/photos_gallery_component.ex`

### Step 1.1: Swap npm package

- [ ] In `assets/package.json`, replace `"alpinejs"` with `"@alpinejs/csp"`:

```json
{
  "name": "kith-assets",
  "private": true,
  "dependencies": {
    "trix": "^2.1.0",
    "@alpinejs/csp": "^3.14.0"
  }
}
```

- [ ] Run: `cd assets && rm -rf node_modules && npm install`
- [ ] Expected: Clean install with `@alpinejs/csp` instead of `alpinejs`

### Step 1.2: Create Alpine component -- sidebar

- [ ] Create `assets/js/alpine/sidebar.js`:

```javascript
import Alpine from "@alpinejs/csp";

Alpine.data("sidebar", () => ({
  sidebarOpen: localStorage.getItem("kith:sidebar") !== "collapsed",
  toggle() {
    this.sidebarOpen = !this.sidebarOpen;
    localStorage.setItem(
      "kith:sidebar",
      this.sidebarOpen ? "expanded" : "collapsed"
    );
  },
}));

Alpine.data("userMenu", () => ({
  userMenu: false,
  toggle() {
    this.userMenu = !this.userMenu;
  },
  close() {
    this.userMenu = false;
  },
}));
```

### Step 1.3: Create Alpine component -- password strength

- [ ] Create `assets/js/alpine/password_strength.js`:

```javascript
import Alpine from "@alpinejs/csp";

Alpine.data("passwordStrength", () => ({
  pw: "",
  get visible() {
    return this.pw.length > 0;
  },
  get barClass() {
    if (this.pw.length < 8) return "bg-error w-1/4";
    if (this.pw.length < 12) return "bg-warning w-1/2";
    if (this.pw.length < 16) return "bg-info w-3/4";
    return "bg-success w-full";
  },
  get textClass() {
    if (this.pw.length < 8) return "text-error";
    if (this.pw.length < 12) return "text-warning";
    if (this.pw.length < 16) return "text-info";
    return "text-success";
  },
  get label() {
    if (this.pw.length < 8) return "Too short";
    if (this.pw.length < 12) return "Fair";
    if (this.pw.length < 16) return "Good";
    return "Strong";
  },
}));
```

### Step 1.4: Create Alpine component -- TOTP challenge

- [ ] Create `assets/js/alpine/totp_challenge.js`:

```javascript
import Alpine from "@alpinejs/csp";

Alpine.data("totpChallenge", () => ({
  recoveryMode: false,
  toggleMode() {
    this.recoveryMode = !this.recoveryMode;
  },
  get modeLabel() {
    return this.recoveryMode
      ? "Use authenticator code instead"
      : "Use a recovery code instead";
  },
  autoSubmit(event) {
    const val = event.target.value;
    if (val.length === 6 && /^\d{6}$/.test(val)) {
      this.$nextTick(() => this.$refs.totpForm.submit());
    }
  },
}));
```

### Step 1.5: Create Alpine component -- recovery codes

- [ ] Create `assets/js/alpine/recovery_codes.js`:

```javascript
import Alpine from "@alpinejs/csp";

Alpine.data("recoveryCodes", (codes) => ({
  codes: codes,
  copied: false,
  async copyAll() {
    await navigator.clipboard.writeText(this.codes.join("\n"));
    this.copied = true;
    setTimeout(() => (this.copied = false), 2000);
  },
  downloadTxt() {
    const blob = new Blob([this.codes.join("\n")], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "kith-recovery-codes.txt";
    a.click();
    URL.revokeObjectURL(url);
  },
}));
```

### Step 1.6: Create Alpine component -- lightbox

- [ ] Create `assets/js/alpine/lightbox.js`:

```javascript
import Alpine from "@alpinejs/csp";

Alpine.data("lightbox", () => ({
  open: false,
  currentSrc: "",
  currentName: "",
  show(src, name) {
    this.currentSrc = src;
    this.currentName = name;
    this.open = true;
  },
  close() {
    this.open = false;
  },
}));
```

### Step 1.7: Create Alpine component -- dismissible

- [ ] Create `assets/js/alpine/dismissible.js`:

```javascript
import Alpine from "@alpinejs/csp";

Alpine.data("dismissible", () => ({
  visible: true,
  dismiss() {
    this.visible = false;
  },
}));
```

### Step 1.8: Update app.js to use CSP build

- [ ] Replace the Alpine section in `assets/js/app.js` (lines 12-15):

**Before:**
```javascript
// Alpine.js for lightbox
import Alpine from "alpinejs"
window.Alpine = Alpine
Alpine.start()
```

**After:**
```javascript
// Alpine.js (CSP build -- no runtime code generation, compatible with strict Content-Security-Policy)
import Alpine from "@alpinejs/csp"
import "./alpine/sidebar"
import "./alpine/password_strength"
import "./alpine/totp_challenge"
import "./alpine/recovery_codes"
import "./alpine/lightbox"
import "./alpine/dismissible"
window.Alpine = Alpine
Alpine.start()
```

### Step 1.9: Update layouts.ex -- sidebar component

- [ ] In `lib/kith_web/components/layouts.ex`, replace the inline `x-data` on the root `<div>` (line 30-36):

**Before:**
```heex
<div
  class="flex h-screen bg-base-100"
  x-data="{
    sidebarOpen: localStorage.getItem('kith:sidebar') !== 'collapsed',
    toggle() {
      this.sidebarOpen = !this.sidebarOpen;
      localStorage.setItem('kith:sidebar', this.sidebarOpen ? 'expanded' : 'collapsed');
    }
  }"
>
```

**After:**
```heex
<div
  class="flex h-screen bg-base-100"
  x-data="sidebar"
>
```

- [ ] Replace the user menu `x-data` (line 88):

**Before:**
```heex
<div class="border-t border-base-300 p-3" x-data="{ userMenu: false }">
```

**After:**
```heex
<div class="border-t border-base-300 p-3" x-data="userMenu">
```

- [ ] Replace `x-on:click="userMenu = !userMenu"` (line 91):

**Before:**
```heex
x-on:click="userMenu = !userMenu"
```

**After:**
```heex
x-on:click="toggle"
```

- [ ] Replace `x-on:click.outside="userMenu = false"` (line 102):

**Before:**
```heex
x-on:click.outside="userMenu = false"
```

**After:**
```heex
x-on:click.outside="close"
```

### Step 1.10: Update registration.ex -- password strength component

- [ ] In `lib/kith_web/live/user_live/registration.ex`, replace the password section (lines 43-81):

**Before:**
```heex
<div
  x-data="{ pw: '' }"
  class="space-y-1"
>
  ...
  x-model="pw"
  ...
  x-show="pw.length > 0"
  x-cloak
  ...
  x-bind:class="pw.length < 8 ? 'bg-error w-1/4' : ..."
  ...
  x-show="pw.length > 0"
  x-cloak
  x-bind:class="pw.length < 8 ? 'text-error' : ..."
  x-text="pw.length < 8 ? 'Too short' : ..."
</div>
```

**After:**
```heex
<div
  x-data="passwordStrength"
  class="space-y-1"
>
  <div class="fieldset mb-2">
    <label for={@form[:password].id}>
      <span class="label mb-1">Password</span>
      <input
        type="password"
        name={@form[:password].name}
        id={@form[:password].id}
        value={Phoenix.HTML.Form.normalize_value("password", @form[:password].value)}
        class="w-full input"
        autocomplete="new-password"
        required
        x-model="pw"
      />
    </label>
  </div>
  <div
    class="h-1.5 w-full rounded-full bg-base-200 overflow-hidden"
    x-show="visible"
    x-cloak
  >
    <div
      class="h-full rounded-full transition-all duration-300"
      x-bind:class="barClass"
    >
    </div>
  </div>

  <p
    class="text-xs"
    x-show="visible"
    x-cloak
    x-bind:class="textClass"
    x-text="label"
  >
  </p>
</div>
```

### Step 1.11: Update totp_challenge.ex

- [ ] In `lib/kith_web/live/user_live/totp_challenge.ex`, replace all inline Alpine:

**Line 10:** `x-data="{ recoveryMode: false }"` -> `x-data="totpChallenge"`

**Line 48 (auto-submit):**

Before:
```heex
x-on:input="if ($event.target.value.length === 6 && /^\d{6}$/.test($event.target.value)) { $nextTick(() => $refs.totpForm.submit()) }"
```

After:
```heex
x-on:input="autoSubmit"
```

**Line 74:** `x-on:click="recoveryMode = !recoveryMode"` -> `x-on:click="toggleMode"`

**Line 75:** `x-text="recoveryMode ? 'Use authenticator code instead' : 'Use a recovery code instead'"` -> `x-text="modeLabel"`

### Step 1.12: Update totp_setup.ex -- recovery codes

- [ ] In `lib/kith_web/live/user_live/totp_setup.ex`:

**Line 23:** Remove the `x-data` from the display grid entirely (it only renders server-side with `:for`).

**Line 30:** Replace `x-data={"{ codes: #{Jason.encode!(@recovery_codes)}, copied: false }"}` with:
```heex
x-data={"recoveryCodes(#{Jason.encode!(@recovery_codes)})"}
```

**Line 35 (copy button):**

Before:
```heex
x-on:click="navigator.clipboard.writeText(codes.join('\\n')); copied = true; setTimeout(() => copied = false, 2000)"
```

After:
```heex
x-on:click="copyAll"
```

**Lines 42-49 (download button):**

Before:
```heex
x-on:click="
  const blob = new Blob([codes.join('\\n')], { type: 'text/plain' });
  ...
"
```

After:
```heex
x-on:click="downloadTxt"
```

### Step 1.13: Update dashboard_live/index.ex -- dismissible banner

- [ ] In `lib/kith_web/live/dashboard_live/index.ex`:

**Line 73:** `x-data="{ visible: true }"` -> `x-data="dismissible"`

Note: `x-show="visible"` on line 74 stays as-is (it references a property defined in the component).

### Step 1.14: Update photos_gallery_component.ex -- lightbox

- [ ] In `lib/kith_web/live/contact_live/photos_gallery_component.ex`:

**Line 151:** `x-data="{lightbox: false, currentSrc: '', currentName: ''}"` -> `x-data="lightbox"`

**Line 152:** `x-on:keydown.escape.window="lightbox = false"` -> `x-on:keydown.escape.window="close"`

**Line 161:**

Before:
```heex
x-on:click={"lightbox = true; currentSrc = '#{photo_url(photo)}'; currentName = '#{photo.file_name}'"}
```

After:
```heex
x-on:click={"show('#{photo_url(photo)}', '#{photo.file_name}')"}
```

**Line 197:** `x-show="lightbox"` -> `x-show="open"`

**Line 201:** `x-on:click.self="lightbox = false"` -> `x-on:click.self="close"`

**Line 205:** `x-bind:src="currentSrc"` stays as-is (property reference).

**Line 206:** `x-bind:alt="currentName"` stays as-is.

**Line 210:** `x-on:click="lightbox = false"` -> `x-on:click="close"`

### Step 1.15: Rebuild and verify

- [ ] Run: `cd /Users/basharqassis/projects/kith && mix esbuild kith`
- [ ] Expected: Build succeeds, no errors
- [ ] Run: `mix tailwind kith`
- [ ] Expected: Build succeeds
- [ ] Start server: `mix phx.server`
- [ ] Navigate to `http://localhost:4000/users/register` in browser
- [ ] Open DevTools Console -- **zero CSP errors expected**
- [ ] Test password strength meter works (type in password field, see color bar)

### Step 1.16: Commit

```bash
git add assets/package.json assets/js/ lib/kith_web/components/layouts.ex \
  lib/kith_web/live/user_live/registration.ex \
  lib/kith_web/live/user_live/totp_challenge.ex \
  lib/kith_web/live/user_live/totp_setup.ex \
  lib/kith_web/live/dashboard_live/index.ex \
  lib/kith_web/live/contact_live/photos_gallery_component.ex
git commit -m "fix: switch Alpine.js to CSP build, extract inline expressions to Alpine.data() components

Replaces alpinejs with @alpinejs/csp to eliminate runtime code generation that
violates the Content-Security-Policy. All inline x-data expressions are now
registered as named Alpine.data() components in assets/js/alpine/."
```

---

## Task 2: Fix Post-Registration Redirect

**Files:**
- Modify: `lib/kith_web/user_auth.ex:303-307`
- Modify: `lib/kith_web/controllers/user_session_controller.ex:9-15`

### Step 2.1: Fix `signed_in_path/1` to handle sockets and default to dashboard

- [ ] In `lib/kith_web/user_auth.ex`, replace lines 301-307:

**Before:**
```elixir
@doc "Returns the path to redirect to after log in."
# the user was already logged in, redirect to settings
def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{user: %Accounts.User{}}}}) do
  ~p"/users/settings"
end

def signed_in_path(_), do: ~p"/"
```

**After:**
```elixir
@doc "Returns the path to redirect to after log in."
# If the user was already logged in (e.g. visiting /login while authenticated),
# send them to settings rather than creating a duplicate session.
def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{user: %Accounts.User{}}}}) do
  ~p"/users/settings"
end

def signed_in_path(_), do: ~p"/dashboard"
```

### Step 2.2: Fix flash message for new registrations

- [ ] In `lib/kith_web/controllers/user_session_controller.ex`, replace lines 9-15:

**Before:**
```elixir
def create(conn, %{"_action" => "confirmed"} = params) do
  create(conn, params, "User confirmed successfully.")
end

def create(conn, params) do
  create(conn, params, "Welcome back!")
end
```

**After:**
```elixir
def create(conn, %{"_action" => "confirmed"} = params) do
  create(conn, params, "User confirmed successfully.")
end

def create(conn, %{"_action" => "registered"} = params) do
  create(conn, params, "Account created successfully!")
end

def create(conn, params) do
  create(conn, params, "Welcome back!")
end
```

- [ ] In `lib/kith_web/live/user_live/registration.ex`, update the form's action to pass the registered action (line 31):

**Before:**
```heex
action={~p"/users/log-in"}
```

**After:**
```heex
action={~p"/users/log-in?_action=registered"}
```

### Step 2.3: Verify

- [ ] Start server, register a new user
- [ ] Expected: Redirect to `/dashboard`, flash says "Account created successfully!"

### Step 2.4: Commit

```bash
git add lib/kith_web/user_auth.ex lib/kith_web/controllers/user_session_controller.ex \
  lib/kith_web/live/user_live/registration.ex
git commit -m "fix: redirect new registrations to /dashboard with correct flash message

signed_in_path/1 now defaults to /dashboard instead of /. New registrations
pass _action=registered so the session controller shows 'Account created
successfully!' instead of 'Welcome back!'."
```

---

## Task 3: Fix API Controller Bugs

**Files:**
- Modify: `lib/kith_web/controllers/api/contact_json.ex`
- Modify: `lib/kith_web/controllers/api/photo_controller.ex`
- Modify: `lib/kith_web/controllers/api/document_controller.ex`
- Modify: `lib/kith_web/controllers/api/relationship_type_controller.ex`
- Modify: `lib/kith_web/controllers/api/tag_controller.ex`
- Modify: `lib/kith_web/controllers/api/call_controller.ex`
- Modify: `lib/kith_web/controllers/api/address_controller.ex`
- Modify: `lib/kith_web/controllers/api/me_controller.ex`

### Step 3.1: Fix field names in contact_json.ex

- [ ] In `lib/kith_web/controllers/api/contact_json.ex`:

**Line 118:** `is_favorite: n.is_favorite` -> `favorite: n.favorite`

**Line 177:** `filename: d.filename` -> `file_name: d.file_name`

**Line 179:** `size_bytes: d.size_bytes` -> `file_size: d.file_size`

**Line 188:** `filename: p.filename` -> `file_name: p.file_name`

### Step 3.2: Fix field names in photo_controller.ex

- [ ] In `lib/kith_web/controllers/api/photo_controller.ex`, line 45 (create action attrs):

**Before:**
```elixir
"filename" => upload.filename,
```

**After:**
```elixir
"file_name" => upload.filename,
"file_size" => upload.path && File.stat!(upload.path).size,
```

Note: Photo.changeset requires `:file_size`, so we must also provide it from the upload.

- [ ] Line 95 (json rendering):

**Before:**
```elixir
%{id: p.id, contact_id: p.contact_id, filename: p.filename, inserted_at: p.inserted_at}
```

**After:**
```elixir
%{id: p.id, contact_id: p.contact_id, file_name: p.file_name, inserted_at: p.inserted_at}
```

### Step 3.3: Fix field names in document_controller.ex

- [ ] In `lib/kith_web/controllers/api/document_controller.ex`, lines 43-45 (create action attrs):

**Before:**
```elixir
"filename" => upload.filename,
"content_type" => upload.content_type,
"size_bytes" => metadata[:size_bytes] || 0,
```

**After:**
```elixir
"file_name" => upload.filename,
"content_type" => upload.content_type,
"file_size" => metadata[:size_bytes] || 0,
```

- [ ] Lines 91-99 (json rendering):

**Before:**
```elixir
defp doc_json(%Document{} = d) do
  %{
    id: d.id,
    contact_id: d.contact_id,
    filename: d.filename,
    content_type: d.content_type,
    size_bytes: d.size_bytes,
    inserted_at: d.inserted_at
  }
```

**After:**
```elixir
defp doc_json(%Document{} = d) do
  %{
    id: d.id,
    contact_id: d.contact_id,
    file_name: d.file_name,
    content_type: d.content_type,
    file_size: d.file_size,
    inserted_at: d.inserted_at
  }
```

### Step 3.4: Fix field name in relationship_type_controller.ex

- [ ] In `lib/kith_web/controllers/api/relationship_type_controller.ex`, line 86:

**Before:**
```elixir
%{id: rt.id, name: rt.name, name_reverse_relationship: rt.name_reverse_relationship}
```

**After:**
```elixir
%{id: rt.id, name: rt.name, reverse_name: rt.reverse_name}
```

### Step 3.5: Fix is_favorite in note_controller.ex

- [ ] In `lib/kith_web/controllers/api/note_controller.ex`:

**Line 132** (toggle_favorite changeset):

**Before:**
```elixir
{:ok, updated} <- note |> Note.changeset(%{is_favorite: value}) |> Repo.update() do
```

**After:**
```elixir
{:ok, updated} <- note |> Note.changeset(%{favorite: value}) |> Repo.update() do
```

**Line 155** (note_json rendering):

**Before:**
```elixir
is_favorite: note.is_favorite,
```

**After:**
```elixir
favorite: note.favorite,
```

### Step 3.6: Fix tag function names in tag_controller.ex

- [ ] In `lib/kith_web/controllers/api/tag_controller.ex`:

**Line 91:** `Contacts.assign_tag(contact, tag)` -> `Contacts.tag_contact(contact, tag)`

Note: `tag_contact/2` returns `{count, nil}` from `Repo.insert_all`, not `{:ok, _}`. Update the case accordingly:

**Before (lines 91-94):**
```elixir
case Contacts.assign_tag(contact, tag) do
  {:ok, _} -> json(conn, %{data: %{status: "assigned"}})
  {:error, reason} -> {:error, :bad_request, inspect(reason)}
end
```

**After:**
```elixir
Contacts.tag_contact(contact, tag)
json(conn, %{data: %{status: "assigned"}})
```

**Line 110:** `Contacts.remove_tag(contact, tag)` -> `Contacts.untag_contact(contact, tag)`

**Line 130:** `Contacts.assign_tag(contact, tag)` -> `Contacts.tag_contact(contact, tag)`

**Line 153:** `Contacts.remove_tag(contact, tag)` -> `Contacts.untag_contact(contact, tag)`

### Step 3.7: Fix create_call arity in call_controller.ex

- [ ] In `lib/kith_web/controllers/api/call_controller.ex`, line 55:

**Before:**
```elixir
{:ok, call} <- Activities.create_call(contact, account_id, attrs) do
```

**After:**
```elixir
{:ok, call} <- Activities.create_call(contact, attrs) do
```

### Step 3.8: Fix create_address arity in address_controller.ex

- [ ] In `lib/kith_web/controllers/api/address_controller.ex`, line 43:

**Before:**
```elixir
{:ok, address} <- Contacts.create_address(contact, account_id, attrs) do
```

**After:**
```elixir
{:ok, address} <- Contacts.create_address(contact, attrs) do
```

### Step 3.9: Stub update_user_settings in me_controller.ex

- [ ] In `lib/kith_web/controllers/api/me_controller.ex`, line 33:

**Before:**
```elixir
case Accounts.update_user_settings(user, safe_attrs) do
```

**After:**
```elixir
# TODO: implement Accounts.update_user_settings/2 -- currently proxying to update_user_profile/2
case Accounts.update_user_profile(user, safe_attrs) do
```

### Step 3.10: Verify compilation

- [ ] Run: `mix compile --warnings-as-errors 2>&1 | grep "error\|undefined\|unknown key"`
- [ ] Expected: No errors about unknown keys or undefined functions in the files we changed

### Step 3.11: Commit

```bash
git add lib/kith_web/controllers/api/
git commit -m "fix: correct API field names and function references across all controllers

- filename -> file_name, size_bytes -> file_size (Photo, Document — create + json)
- is_favorite -> favorite (Note — changeset + json, in both contact_json and note_controller)
- name_reverse_relationship -> reverse_name (RelationshipType)
- assign_tag/2 -> tag_contact/2, remove_tag/2 -> untag_contact/2 (Tags)
- create_call/3 -> create_call/2, create_address/3 -> create_address/2
- Stub update_user_settings via update_user_profile"
```

---

## Task 4: Fix Timezone Validation and Unqualified Module References

**Files:**
- Modify: `lib/kith/accounts/account.ex:51-63`
- Modify: `lib/kith/accounts/user.ex:165-177`
- Modify: `lib/kith/contacts.ex:11-29`

### Step 4.1: Replace Tzdata with Tz.TimeZoneDatabase

- [ ] In `lib/kith/accounts/account.ex`, replace the `validate_timezone` function (lines 51-63):

**Before:**
```elixir
defp validate_timezone(changeset) do
  case get_change(changeset, :timezone) do
    nil ->
      changeset

    tz ->
      if Tzdata.zone_exists?(tz) do
        changeset
      else
        add_error(changeset, :timezone, "is not a valid IANA timezone")
      end
  end
end
```

**After:**
```elixir
defp validate_timezone(changeset) do
  case get_change(changeset, :timezone) do
    nil ->
      changeset

    tz ->
      case Tz.TimeZoneDatabase.time_zone_periods_from_wall_datetime(~N[2000-01-01 00:00:00], tz) do
        {:error, :time_zone_not_found} ->
          add_error(changeset, :timezone, "is not a valid IANA timezone")

        _ ->
          changeset
      end
  end
end
```

### Step 4.2: Same fix in user.ex

- [ ] In `lib/kith/accounts/user.ex`, apply the identical replacement to the `validate_timezone` function (lines 165-177). Same before/after as Step 4.1.

### Step 4.3: Add Activity and Call aliases in contacts.ex

- [ ] In `lib/kith/contacts.ex`, add after the existing alias block (after line 29):

**Add this line after the closing `}` of the Contacts alias block:**
```elixir
alias Kith.Activities.{Activity, Call}
```

### Step 4.4: Fix field name bugs in recent_activity/2

Since we're already fixing the aliases for this function, also fix two incorrect field references that would cause SQL errors at runtime.

- [ ] In `lib/kith/contacts.ex`, line 1612:

**Before:**
```elixir
occurred_at: n.created_at,
```

**After:**
```elixir
occurred_at: n.inserted_at,
```

Note: The `Note` schema has no `created_at` field. `inserted_at` is the closest equivalent.

- [ ] Line 1638:

**Before:**
```elixir
occurred_at: c.called_at,
```

**After:**
```elixir
occurred_at: c.occurred_at,
```

Note: The `Call` schema field is `:occurred_at`, not `:called_at`.

### Step 4.5: Verify

- [ ] Run: `mix compile --warnings-as-errors 2>&1 | grep -i "tzdata\|undefined.*Activity\|undefined.*Call"`
- [ ] Expected: No Tzdata or Activity/Call warnings

### Step 4.6: Commit

```bash
git add lib/kith/accounts/account.ex lib/kith/accounts/user.ex lib/kith/contacts.ex
git commit -m "fix: replace Tzdata with Tz.TimeZoneDatabase, add Activity/Call aliases, fix recent_activity fields

Tzdata module is not in the dependency tree. Uses Tz.TimeZoneDatabase for
timezone validation instead. Adds missing aliases for Kith.Activities.Activity
and Kith.Activities.Call in Kith.Contacts. Fixes n.created_at -> n.inserted_at
and c.called_at -> c.occurred_at in recent_activity/2."
```

---

## Task 5: Add Vendor Download Mix Task

**Files:**
- Create: `lib/mix/tasks/assets_vendor.ex`
- Modify: `mix.exs:142`

### Step 5.1: Create the mix task

- [ ] Create `lib/mix/tasks/assets_vendor.ex`:

```elixir
defmodule Mix.Tasks.Assets.Vendor do
  @moduledoc "Downloads vendored JS files (daisyUI, heroicons) for the asset pipeline."
  @shortdoc "Downloads vendored JS dependencies"

  use Mix.Task

  @vendor_dir "assets/vendor"
  @files [
    {"daisyui.js",
     "https://github.com/saadeghi/daisyui/releases/latest/download/daisyui.js"},
    {"daisyui-theme.js",
     "https://github.com/saadeghi/daisyui/releases/latest/download/daisyui-theme.js"}
  ]

  @impl true
  def run(_args) do
    File.mkdir_p!(@vendor_dir)

    for {filename, url} <- @files do
      dest = Path.join(@vendor_dir, filename)

      if File.exists?(dest) do
        Mix.shell().info("#{filename} already exists, skipping")
      else
        Mix.shell().info("Downloading #{filename}...")

        case System.cmd("curl", ["-sL", "-o", dest, url]) do
          {_, 0} -> Mix.shell().info("  -> #{dest}")
          {err, _} -> Mix.raise("Failed to download #{filename}: #{err}")
        end
      end
    end

    # heroicons.js is generated locally, not downloaded
    heroicons = Path.join(@vendor_dir, "heroicons.js")

    unless File.exists?(heroicons) do
      Mix.shell().info("Generating heroicons.js Tailwind plugin...")
      File.write!(heroicons, heroicons_plugin())
      Mix.shell().info("  -> #{heroicons}")
    end
  end

  defp heroicons_plugin do
    """
    // Heroicons Tailwind v4 plugin
    // Generated by mix assets.vendor -- reads SVGs from deps/heroicons
    const plugin = require("tailwindcss/plugin")
    const fs = require("fs")
    const path = require("path")

    module.exports = plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "../../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"],
      ]
      icons.forEach(([suffix, dir]) => {
        let fullDir = path.join(iconsDir, dir)
        if (!fs.existsSync(fullDir)) return
        fs.readdirSync(fullDir).forEach((file) => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = { name, fullPath: path.join(fullDir, file) }
        })
      })
      matchComponents(
        {
          hero: ({ name, fullPath }) => {
            let content = fs.readFileSync(fullPath).toString().replace(/\\r?\\n|\\r/g, "")
            let size = theme("spacing.6", "1.5rem")
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              "-webkit-mask": `var(--hero-${name})`,
              mask: `var(--hero-${name})`,
              "mask-repeat": "no-repeat",
              "background-color": "currentColor",
              "vertical-align": "middle",
              display: "inline-block",
              width: size,
              height: size,
            }
          },
        },
        { values }
      )
    })
    """
  end
end
```

### Step 5.2: Hook into mix setup

- [ ] In `mix.exs`, update the `setup` alias (line 142):

**Before:**
```elixir
setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
```

**After:**
```elixir
setup: ["deps.get", "ecto.setup", "assets.setup", "assets.vendor", "assets.build"],
```

### Step 5.3: Verify

- [ ] Run: `rm assets/vendor/daisyui.js assets/vendor/daisyui-theme.js assets/vendor/heroicons.js`
- [ ] Run: `mix assets.vendor`
- [ ] Expected: All three files downloaded/generated
- [ ] Run: `mix tailwind kith && mix esbuild kith`
- [ ] Expected: Both build successfully

### Step 5.4: Commit

```bash
git add lib/mix/tasks/assets_vendor.ex mix.exs
git commit -m "feat: add mix assets.vendor task to download vendored JS dependencies

Downloads daisyui.js, daisyui-theme.js and generates heroicons.js plugin.
Hooked into mix setup so new developers get vendor files automatically."
```

---

## Task 6: Clean Up Warnings

**Files:**
- Modify: `lib/kith_web/controllers/api/contact_controller.ex`
- Modify: `lib/kith_web/controllers/api/me_controller.ex`
- Modify: `lib/kith_web/controllers/api/statistics_controller.ex`
- Modify: `lib/kith_web/controllers/api/gender_controller.ex`
- Modify: `lib/kith_web/controllers/api/relationship_type_controller.ex`
- Modify: `lib/kith/sentry_event_handler.ex`
- Modify: `lib/kith/contacts/note.ex`
- Modify: `lib/kith/reminders.ex`
- Modify: `lib/kith/workers/immich_sync_worker.ex`
- Modify: `lib/kith/contacts.ex`

### Step 6.1: Fix unused variable warnings

- [ ] `contact_controller.ex:109` -- `def create(conn, _params)` -> `def create(_conn, _params)`
- [ ] `contact_controller.ex:132` -- `def update(conn, ...)` -> `def update(_conn, ...)`
- [ ] `contact_controller.ex:253` -- `def merge(conn, ...)` -> `def merge(_conn, ...)`
- [ ] `me_controller.ex:39` -- `def update(conn, _params)` -> `def update(_conn, _params)`
- [ ] `sentry_event_handler.ex:57` -- `{key, value}` -> `{key, _value}`
- [ ] `reminders.ex:410` -- `= rule` -> `= _rule`
- [ ] `reminders.ex:414` -- `= rule` -> `= _rule`
- [ ] `contacts.ex:909` -- `merge_tags(account_id,` -> `merge_tags(_account_id,`
- [ ] `immich_sync_worker.ex:95` -- `handle_matches(account,` -> `handle_matches(_account,`

### Step 6.2: Fix unused alias/import warnings

- [ ] `statistics_controller.ex:4` -- Remove unused `Contacts` from alias: `alias Kith.{Contacts, Repo}` -> `alias Kith.Repo`
- [ ] `statistics_controller.ex:7` -- Remove unused `import Ecto.Query`
- [ ] `gender_controller.ex:6` -- Remove unused `alias Kith.Scope, as: TenantScope`
- [ ] `relationship_type_controller.ex:7` -- Remove unused `alias Kith.Scope, as: TenantScope`

### Step 6.3: Fix note.ex scrubber warnings

- [ ] In `lib/kith/contacts/note.ex`, remove unused module attributes at lines 17-18:

```elixir
# Remove these two lines:
@allowed_tags ~w(p br strong em ul ol li a h1 h2 h3 h4 h5 h6 blockquote)
@allowed_attributes ~w(href)
```

- [ ] Fix the `for tag` warning at line 49 -- prefix with underscore if truly unused or use the variable properly. The existing code uses `Meta.allow_tag_with_these_attributes(tag, [])` which should use it, so investigate the actual scrubber macro expansion.

### Step 6.4: Verify

- [ ] Run: `mix compile --warnings-as-errors 2>&1 | tail -5`
- [ ] Expected: Clean compilation with zero warnings

### Step 6.5: Commit

```bash
git add lib/
git commit -m "chore: fix all compilation warnings -- unused vars, aliases, imports"
```

---

## Task 7: Finalize Playwright Smoke Tests

**Files:**
- Modify: `.gitignore`
- Modify: `e2e/smoke.spec.ts`
- Keep: `playwright.config.ts`
- Keep: `package.json`

### Step 7.1: Update .gitignore

- [ ] Add Playwright artifacts to `.gitignore`:

```
# Playwright
/test-results/
/playwright-report/
.playwright-mcp/
/node_modules/
```

### Step 7.2: Update smoke tests for fixed behavior

- [ ] In `e2e/smoke.spec.ts`, update these tests:

**Registration flow test** -- update expected URL:
```typescript
// Was: await page.waitForURL(/\/(users\/confirm-email|dashboard)/, { timeout: 10_000 });
await page.waitForURL(/\/dashboard/, { timeout: 10_000 });
```

**Navigation link tests** -- use `waitForURL` with longer timeout for LiveView navigate:
```typescript
test("Registration -> Login link works", async ({ page }) => {
  await page.goto("/users/register");
  await page.getByRole("link", { name: /log in/i }).click();
  await expect(page).toHaveURL(/\/users\/log-in/, { timeout: 10_000 });
});
```

**CSP audit tests** -- should now pass (expect zero errors). Keep the tests as-is; they will validate the Alpine CSP fix.

### Step 7.3: Run full test suite

- [ ] Start the server: `mix phx.server &`
- [ ] Run: `npx playwright test --reporter=list`
- [ ] Expected: **28/28 passing**

### Step 7.4: Commit

```bash
git add .gitignore e2e/ playwright.config.ts package.json package-lock.json
git commit -m "test: add Playwright e2e smoke tests (28 tests across 10 suites)

Covers health endpoint, auth pages, auth redirects, registration flow,
login flow, CSP/JS health audit, static assets, API auth, navigation,
and LiveView WebSocket connectivity."
```

---

## Execution Order

Tasks 1-5 are independent and can be parallelized. Task 6 (warnings) should run after Task 3 (API fixes) since both touch `relationship_type_controller.ex`. Task 7 depends on all others (tests verify the fixes). Recommended order for serial execution:

1. **Task 3** (API fixes) -- quick wins, many files
2. **Task 4** (Timezone + aliases) -- small, targeted
3. **Task 6** (Warnings cleanup) -- small changes
4. **Task 2** (Auth redirect) -- small but important
5. **Task 5** (Vendor task) -- new file
6. **Task 1** (Alpine CSP) -- largest, most files
7. **Task 7** (Playwright finalization) -- verify everything
