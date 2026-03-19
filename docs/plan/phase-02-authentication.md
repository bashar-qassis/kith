# Phase 02: Authentication & Security

> **Status:** Implemented
> **Depends on:** Phase 01 (Foundation)
> **Blocks:** Phase 03, Phase 04, Phase 05, Phase 06, Phase 07, Phase 08, Phase 09, Phase 10, Phase 11, Phase 12

## Overview

This phase implements all authentication, authorization, and session-security features for Kith. It covers email/password login (via `phx_gen_auth`), TOTP two-factor authentication, WebAuthn/passkeys, social OAuth via `assent`, API bearer tokens, rate limiting, session management, secure headers, and the role-based authorization foundation (`Kith.Policy`). No feature requiring a logged-in user can ship until this phase is complete.

---

## Tasks

### TASK-02-01: phx_gen_auth Integration
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-01-01, TASK-01-02, TASK-01-03
**Description:**
Run `mix phx.gen.auth Accounts User users` and customize the generated code to align with the Kith domain ERD. The generated migration must be modified to add: `account_id` FK (references `accounts`, not null), `role` column (string, default `"editor"`, not null), and additional profile columns (`locale`, `timezone`, `display_name_format`, `currency`, `temperature_unit`, `default_profile_tab`, `me_contact_id` FK). The `users` table must have a unique index on `email`. The generated `Accounts` context, `User` schema, and `UserToken` schema must be adapted — not replaced — to fit within the existing `Kith.Accounts` context boundary. Registration creates both an `Account` and a `User` (the first user on an account is always `admin`).

**Acceptance Criteria:**
- [ ] `mix phx.gen.auth Accounts User users` output is integrated (not a raw copy-paste)
- [ ] `users` table has `account_id` FK, `role` column with default `"editor"`, and all profile columns
- [ ] `user_tokens` table exists with standard phx_gen_auth columns
- [ ] `Kith.Accounts.register_user/1` creates an `Account` and the first `User` with role `admin` inside an `Ecto.Multi` transaction
- [ ] `Kith.Accounts.get_user_by_email_and_password/2` works correctly
- [ ] `fetch_current_user` plug loads user + preloads account
- [ ] All generated tests pass with modifications

**Safeguards:**
> Do not blindly accept phx_gen_auth output. The generated migration, context, and plugs must be reviewed line-by-line and modified to match the Kith domain model. Do not create a separate Auth context — integrate into `Kith.Accounts`.

**Notes:**
- The `accounts` table migration should be created in this phase if not already present from Phase 01
- `me_contact_id` FK references `contacts` table — this FK will be nullable and the contacts table won't exist yet; use a migration with `references(:contacts, on_delete: :nilify_all)` and add it in a later migration if needed
- Ensure `account_id` is included in all session-related queries for tenant isolation

---

### TASK-02-02: Email Verification Flow
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-02-01
**Description:**
Implement email verification gated by the `SIGNUP_DOUBLE_OPTIN` environment variable. When enabled, new users receive a verification email (via Swoosh) containing a signed token. The token is stored in `user_tokens` with `context: "confirm"`. Users who have not verified see a "Please verify your email" banner and are restricted from accessing the app until verified. The verification link confirms the user and redirects to the dashboard. If `SIGNUP_DOUBLE_OPTIN` is not set or is `"false"`, users are auto-confirmed on registration.

**Acceptance Criteria:**
- [ ] When `SIGNUP_DOUBLE_OPTIN=true`, registration sends a verification email via Swoosh
- [ ] Verification token is stored in `user_tokens` with context `"confirm"`
- [ ] Clicking the verification link confirms the user's email and redirects to dashboard
- [ ] Unverified users cannot access protected routes (redirected to "check your email" page)
- [ ] "Resend verification email" link available on the pending page
- [ ] When `SIGNUP_DOUBLE_OPTIN` is unset or `"false"`, users are auto-confirmed
- [ ] Verification tokens expire after 7 days

**Safeguards:**
> The `SIGNUP_DOUBLE_OPTIN` env var must be read at runtime via `Application.get_env/3` (set in `runtime.exs`), not compile-time config. Ensure the verification email is sent asynchronously (Oban mailer queue) so registration does not block on SMTP.

**Notes:**
- Use the Swoosh `Kith.Mailer` module configured in Phase 01
- Verification email should include the app name and a clear call-to-action button

---

### TASK-02-03: Password Reset Flow
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-02-01
**Description:**
Implement the forgot-password flow: user submits email on `/auth/reset_password`, receives a reset token via email, clicks link to `/auth/reset_password/:token`, enters new password, all existing sessions are invalidated. The reset token is stored in `user_tokens` with `context: "reset_password"` and expires after 1 hour. The response to the forgot-password form must not reveal whether the email exists in the system (always show "If an account exists, we sent a reset link").

**Acceptance Criteria:**
- [ ] `GET /auth/reset_password` renders forgot-password form
- [ ] `POST /auth/reset_password` sends reset email if user exists; always shows success message regardless
- [ ] Reset token stored in `user_tokens` with context `"reset_password"`, expires after 1 hour
- [ ] `GET /auth/reset_password/:token` renders new-password form
- [ ] `PUT /auth/reset_password/:token` updates password and invalidates all existing sessions for that user
- [ ] Expired or invalid tokens show a clear error message
- [ ] Password reset email sent via Oban mailer queue

**Safeguards:**
> Never reveal whether an email address exists in the system. The forgot-password response must be identical whether the email is registered or not. This prevents user enumeration attacks.

**Notes:**
- phx_gen_auth generates most of this; customize the templates and ensure session invalidation is complete
- Invalidating sessions means deleting all `user_tokens` where `context: "session"` for that user

---

### TASK-02-04: Account Registration & Signup Controls
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-02-01
**Description:**
Implement registration with proper validation and the `DISABLE_SIGNUP` environment variable gate. When `DISABLE_SIGNUP=true`, the registration route returns 403 and the registration link is hidden from the login page. Password validation requires minimum 12 characters; complexity requirements (uppercase, number, special char) are optional and not enforced in v1. Email uniqueness is enforced at both changeset and database level.

**Acceptance Criteria:**
- [ ] Registration form at `GET /auth/register` with email and password fields
- [ ] Password validation: minimum 12 characters, maximum 72 characters (bcrypt limit)
- [ ] Email uniqueness enforced via changeset validation and unique database index
- [ ] When `DISABLE_SIGNUP=true`: `GET /auth/register` returns 403; login page hides registration link
- [ ] When `DISABLE_SIGNUP` is unset or `"false"`: registration is open
- [ ] First user on a new account gets `role: "admin"`
- [ ] Registration creates both `Account` and `User` atomically

**Safeguards:**
> Read `DISABLE_SIGNUP` at runtime, not compile-time. The 72-character bcrypt limit is real — passwords longer than 72 bytes are silently truncated by bcrypt. Validate max length explicitly.

**Notes:**
- The `DISABLE_SIGNUP` check should be a plug so it can be applied to the registration route group
- Consider adding a `Kith.Accounts.signup_enabled?/0` helper read from runtime config

---

### TASK-02-05: TOTP Setup Flow
**Priority:** High
**Effort:** M
**Depends on:** TASK-02-01
**Description:**
Implement TOTP two-factor authentication setup using the `pot` library. The flow: user navigates to Settings > Security, clicks "Enable Two-Factor Authentication", system generates a random secret, displays a QR code (as a data URL using an Elixir QR code library such as `eqrcode`), user scans with their authenticator app (e.g., Google Authenticator), enters the current 6-digit code to confirm, system verifies the code via `pot`, stores the secret (encrypted at rest in the `totp_secret` column), and sets `totp_enabled: true`. The QR code encodes a `otpauth://` URI with the issuer set to the `TOTP_ISSUER` env var (default: `"Kith"`).

**Acceptance Criteria:**
- [ ] Settings > Security has "Enable Two-Factor Authentication" button (only when TOTP is not enabled)
- [ ] Clicking the button generates a new TOTP secret via `pot`
- [ ] QR code displayed as an inline data URL (PNG) encoding the `otpauth://totp/ISSUER:EMAIL?secret=SECRET&issuer=ISSUER` URI
- [ ] Manual entry secret also displayed as text (for users who can't scan)
- [ ] User must enter a valid 6-digit TOTP code to confirm setup
- [ ] On successful confirmation: `totp_secret` saved (encrypted), `totp_enabled` set to `true`
- [ ] Recovery codes generated and displayed (see TASK-02-07)
- [ ] Invalid confirmation code shows error, does not enable TOTP

**Safeguards:**
> The TOTP secret must be encrypted at application level before storing in the database. Use `Cloak` or a custom `Ecto.Type` with AES-256-GCM encryption keyed from `SECRET_KEY_BASE`. Never store the raw base32 secret in plaintext. The QR code must be generated server-side as a data URL — do not use any external QR code service.

**Notes:**
- Add `eqrcode` to mix.exs dependencies for QR code generation
- The `TOTP_ISSUER` env var defaults to `"Kith"` if not set
- `pot` uses base32-encoded secrets by default; ensure the secret encoding matches what authenticator apps expect

---

### TASK-02-06: TOTP Login Challenge
**Priority:** High
**Effort:** S
**Depends on:** TASK-02-05
**Description:**
After a user with TOTP enabled successfully enters their email and password, redirect them to a TOTP challenge screen at `/auth/two_factor` instead of creating a session. The challenge screen presents a 6-digit code input. The code is validated via `pot.valid_totp/2` with a window of 1 (allowing the current and previous 30-second period). On success, the session is created and the user is redirected to the dashboard. On failure, an error message is displayed. The intermediate state (password verified, awaiting TOTP) is stored in a short-lived signed token in the session, not by creating a full user session.

**Acceptance Criteria:**
- [ ] Login with correct email+password for a TOTP-enabled user redirects to `/auth/two_factor`
- [ ] TOTP challenge page shows a 6-digit code input and a "Use recovery code" link
- [ ] Valid TOTP code (current or previous window) creates a full session and redirects to dashboard
- [ ] Invalid TOTP code shows error message, does not create session
- [ ] The intermediate "password verified" state uses a signed, short-lived token (5-minute expiry) — not a full session
- [ ] If the intermediate token expires, user must re-enter password
- [ ] Users without TOTP enabled proceed directly to session creation after password verification

**Safeguards:**
> The intermediate token must be cryptographically signed and have a short TTL (5 minutes max). Never store the user ID in a plain cookie between password verification and TOTP verification. An attacker who intercepts the intermediate state should not be able to escalate to a full session without a valid TOTP code.

**Notes:**
- Use `Phoenix.Token.sign/4` for the intermediate token
- The `window: 1` option in `pot.valid_totp/2` allows for clock drift of one 30-second period

---

### TASK-02-07: Recovery Codes
**Priority:** High
**Effort:** S
**Depends on:** TASK-02-05
**Description:**
Generate **8** single-use backup recovery codes when TOTP is first enrolled. Each code is an 8-character alphanumeric string formatted as `XXXX-XXXX` (e.g., `a1b2-c3d4`). The raw codes are displayed to the user exactly once with the warning "Store these somewhere safe. You won't be able to see them again." The codes are stored as **bcrypt hashes** in a `user_recovery_codes` table. When used in place of a TOTP code on the login challenge screen, the matching record is deleted (single-use — the code is immediately consumed and cannot be reused). Settings > Security shows the count of remaining (unused) recovery codes. A "Regenerate recovery codes" option generates a new set of 8 codes and immediately invalidates (deletes) all previous codes.

**Acceptance Criteria:**
- [ ] 8 recovery codes generated on TOTP enrollment, displayed once to the user
- [ ] Warning text: "Store these somewhere safe. You won't be able to see them again."
- [ ] Codes stored as bcrypt hashes in `user_recovery_codes` table (not plaintext)
- [ ] Recovery code can be used in place of TOTP code on the two-factor challenge screen
- [ ] Used recovery code is deleted immediately on use (single-use — second attempt with the same code fails)
- [ ] Settings > Security displays the count of remaining (unconsumed) recovery codes
- [ ] "Regenerate recovery codes" in Settings > Security creates 8 new codes and deletes all old codes atomically
- [ ] Regeneration requires current TOTP code or a valid remaining recovery code for confirmation
- [ ] Display page is not cacheable: `Cache-Control: no-store` header set

**Safeguards:**
> Recovery codes must be cryptographically random (use `:crypto.strong_rand_bytes/1`). Never log recovery codes. The display page must not be cacheable (set `Cache-Control: no-store`). Bcrypt hashing each code is intentional — it prevents database-level exposure from being directly usable. Regeneration must be atomic: delete old codes and insert new codes in the same database transaction.

**Notes:**
- Format codes as `XXXX-XXXX` for readability (8 alphanumeric chars with a dash in the middle)
- Store in a `user_recovery_codes` table with columns: `id`, `user_id`, `code_hash`, `inserted_at`
- When validating, iterate over all unused codes and `Bcrypt.verify_pass/2` each one (no `used_at` needed — delete on use rather than marking used)

---

### TASK-02-08: TOTP Disable Flow
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-02-05, TASK-02-07
**Description:**
Allow users to disable TOTP from Settings > Security. Disabling requires the user to enter a valid current TOTP code or a valid recovery code as confirmation. On disable: set `totp_enabled: false`, clear `totp_secret`, delete all recovery codes. Log an audit event: `{action: "totp_disabled", user_id: user.id}`.

**Acceptance Criteria:**
- [ ] "Disable Two-Factor Authentication" button in Settings > Security (only when TOTP is enabled)
- [ ] Clicking shows a confirmation dialog requiring a TOTP code or recovery code
- [ ] Valid code disables TOTP: `totp_enabled` set to `false`, `totp_secret` cleared, all recovery codes deleted
- [ ] Invalid code shows error, TOTP remains enabled
- [ ] Audit log entry created for TOTP disable event
- [ ] After disabling, login no longer requires TOTP challenge

**Safeguards:**
> Ensure the `totp_secret` is fully cleared (set to `nil`) on disable, not just the `totp_enabled` flag. Leftover secrets are a security risk if TOTP is re-enabled later with the old secret.

**Notes:**
- The audit log entry should be created via an Oban job (async) to avoid blocking the disable flow
- Use `Ecto.Multi` to atomically clear secret, disable flag, and delete recovery codes

---

### TASK-02-09: WebAuthn Registration
**Priority:** High
**Effort:** L
**Depends on:** TASK-02-01
**Description:**
Implement WebAuthn credential registration using the `wax` library. The flow involves two HTTP endpoints: `POST /auth/webauthn/register/challenge` generates and returns a challenge (stored server-side in the session), and `POST /auth/webauthn/register/complete` receives the attestation response from the browser, validates it via `Wax.register/3`, and stores the credential in a `webauthn_credentials` table. Users can register multiple credentials (e.g., Touch ID, a security key). Settings > Security displays a list of registered credentials with names, creation dates, last-used timestamps, and a "Remove" button for each. Removing a credential requires confirmation.

**Acceptance Criteria:**
- [ ] `POST /auth/webauthn/register/challenge` returns a challenge JSON payload (publicKey options)
- [ ] Challenge is stored server-side (in session or short-lived ETS/DB entry)
- [ ] `POST /auth/webauthn/register/complete` validates the attestation via `Wax.register/3`
- [ ] Valid attestation stores credential in `webauthn_credentials` table: `user_id`, `credential_id` (binary), `public_key` (binary), `sign_count` (integer), `name` (user-provided), `inserted_at`, `last_used_at`
- [ ] Users can register multiple credentials
- [ ] Settings > Security lists all registered credentials with name, created date, last used date
- [ ] Users can remove individual credentials (with confirmation dialog)
- [ ] Cannot remove last credential if it would leave user with no login method (check: password exists OR other credentials exist OR OAuth linked)

**Safeguards:**
> The Relying Party ID (`rp.id`) must match `KITH_HOSTNAME` exactly. A mismatch will cause all WebAuthn operations to fail silently in the browser. Validate this in tests. Store credential IDs and public keys as binary — do not base64-encode for storage.

**Notes:**
- `webauthn_credentials` table: `id`, `user_id` (FK), `credential_id` (binary, unique), `public_key` (binary), `sign_count` (integer), `name` (string), `last_used_at` (utc_datetime), timestamps
- The `wax` library config needs: `origin` (from `KITH_HOSTNAME`), `rp_id` (hostname without port)
- JavaScript on the client side uses the Web Authentication API (`navigator.credentials.create()`) — this is a LiveView hook or a small JS module

---

### TASK-02-10: WebAuthn Authentication
**Priority:** High
**Effort:** M
**Depends on:** TASK-02-09
**Description:**
Implement WebAuthn authentication (login) as an alternative to password+TOTP. Two endpoints: `POST /auth/webauthn/authenticate/challenge` generates an authentication challenge (including allowed credential IDs for the user, if email was provided), and `POST /auth/webauthn/authenticate/complete` validates the assertion via `Wax.authenticate/5`, updates the sign count, creates a full session, and redirects to dashboard. If a user has no registered WebAuthn credentials, they fall back to the standard password (+TOTP) flow. The login page shows a "Sign in with passkey" button that triggers the WebAuthn flow.

**Acceptance Criteria:**
- [ ] Login page has "Sign in with passkey" button
- [ ] `POST /auth/webauthn/authenticate/challenge` returns challenge with allowed credentials
- [ ] `POST /auth/webauthn/authenticate/complete` validates assertion via `Wax.authenticate/5`
- [ ] Successful authentication creates a full session (bypasses TOTP — WebAuthn is inherently 2FA)
- [ ] Sign count is updated on the credential after successful authentication
- [ ] `last_used_at` timestamp updated on the credential
- [ ] Sign count regression (replay attack indicator) rejects authentication and flags the credential
- [ ] Falls back to password+TOTP if user has no WebAuthn credentials

**Safeguards:**
> WebAuthn authentication bypasses TOTP because passkeys are inherently multi-factor (possession + biometric/PIN). This is the correct security model — do not require TOTP on top of WebAuthn. However, always verify the sign count to detect cloned credentials.

**Notes:**
- The "Sign in with passkey" flow can be initiated without entering an email first (discoverable credentials / resident keys) or after entering an email (server provides allowed credential IDs)
- Use `Wax.authenticate/5` with the stored public key and previous sign count

---

### TASK-02-11: Social OAuth Configuration (assent)
**Priority:** High
**Effort:** M
**Depends on:** TASK-02-01
**Description:**
Configure the `assent` library for GitHub and Google OAuth providers with PKCE support. Create OAuth routes: `GET /auth/:provider` (redirect to provider), `GET /auth/:provider/callback` (handle callback). The callback handler: (1) exchanges the authorization code for tokens, (2) fetches user info from the provider, (3) looks up an existing `UserIdentity` record by provider+uid, (4) if found, logs in the associated user, (5) if not found and user is not logged in, creates a new `Account` + `User` + `UserIdentity` (if signup is enabled), (6) if not found and user is logged in, links the identity to the current user. The `user_identities` table stores: `user_id`, `provider`, `uid`, `access_token` (encrypted), `refresh_token` (encrypted), `token_url`, `expires_at`. Confirm PKCE support by verifying that `assent` sends `code_verifier` and `code_challenge` in the authorization flow.

**Acceptance Criteria:**
- [ ] `GET /auth/github` redirects to GitHub OAuth with PKCE parameters (code_challenge, code_challenge_method)
- [ ] `GET /auth/github/callback` exchanges code, fetches user info, creates or finds user
- [ ] `GET /auth/google` and `/auth/google/callback` work similarly for Google
- [ ] `user_identities` table created with columns: `id`, `user_id` (FK), `provider`, `uid`, `access_token` (encrypted), `access_token_secret` (encrypted), `refresh_token` (encrypted), `token_url`, `expires_at`, timestamps
- [ ] Unique index on `(provider, uid)` in `user_identities`
- [ ] New OAuth user: creates Account + User (role: admin) + UserIdentity if signup enabled
- [ ] New OAuth user with signup disabled: shows error, does not create account
- [ ] Existing OAuth user: logs in, updates tokens in UserIdentity
- [ ] PKCE verification: documented confirmation that `assent` sends `code_verifier`/`code_challenge`
- [ ] OAuth provider config read from env vars: `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- [ ] Users who register via OAuth are considered email-verified (the OAuth provider has already confirmed the address). `confirmed_at` is set to `NOW()` at account creation — no confirmation email is sent for OAuth registrations.

**Safeguards:**
> Verify PKCE by inspecting the authorization URL parameters in tests — confirm `code_challenge` and `code_challenge_method=S256` are present. Without PKCE, the OAuth flow is vulnerable to authorization code interception. Encrypt `access_token` and `refresh_token` at the application level before storing (same encryption approach as TOTP secret).

**Notes:**
- `assent` strategies: `Assent.Strategy.Github`, `Assent.Strategy.Google`
- Store provider config in `runtime.exs` under `config :kith, :oauth_providers`
- Handle the case where a user tries to OAuth-login with a provider linked to a different account — show a clear error

---

### TASK-02-12: OAuth Account Linking
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-02-11
**Description:**
Allow logged-in users to link and unlink OAuth providers from Settings > Security. The settings page shows the status of each configured provider (GitHub, Google) — either "Linked" with the provider username/email and an "Unlink" button, or "Not linked" with a "Link" button. Linking redirects through the same OAuth flow but associates the identity with the current user instead of creating a new account. Unlinking deletes the `UserIdentity` record. Prevent unlinking if it would leave the user with no login method (no password set AND no other OAuth provider AND no WebAuthn credentials).

**Acceptance Criteria:**
- [ ] Settings > Security shows OAuth provider status (linked/unlinked) for GitHub and Google
- [ ] "Link" button initiates OAuth flow and associates identity with current user
- [ ] "Unlink" button removes the `UserIdentity` record
- [ ] Cannot unlink if it would leave user with no login method — show error message
- [ ] Login method check considers: password set, other OAuth providers linked, WebAuthn credentials registered
- [ ] After linking, the provider shows as "Linked" with provider display name

**Safeguards:**
> The "no login method" check must be atomic — use a database transaction that checks all login methods before deleting the identity. A race condition here could lock a user out of their account.

**Notes:**
- A user "has a password" if `hashed_password` is not null on the user record
- The unlink confirmation should clearly state what will happen

---

### TASK-02-13: API Bearer Token Generation
**Priority:** High
**Effort:** S
**Depends on:** TASK-02-01
**Description:**
Implement bearer token generation for API authentication. `POST /api/auth/token` accepts `{email, password}` in the request body, validates credentials, and returns `{token, expires_at}`. The token is a random 32-byte value, base64url-encoded. It is stored in `user_tokens` with `context: "api"` and a hashed version (SHA-256) of the token. Tokens do not expire by default (long-lived), but `expires_at` is returned as `null` to indicate no expiry. All API endpoints (except `POST /api/auth/token`) require a valid Bearer token in the `Authorization` header, validated by the `fetch_api_user` plug. The plug hashes the incoming token, looks it up in `user_tokens`, and loads the user + account.

Tokens are **account-scoped**: each token is tied to a specific `account_id` and a specific `user_id`. Token claims stored in the DB record: `{user_id, account_id, jti}`. The `fetch_api_user` plug must verify both that the user is active and that the account membership is active before granting access.

**Acceptance Criteria:**
- [ ] `POST /api/auth/token` with valid email+password returns `{token: "...", expires_at: null}` with status 201
- [ ] `POST /api/auth/token` with invalid credentials returns 401 with RFC 7807 error
- [ ] Token stored in `user_tokens` as SHA-256 hash with `context: "api"`, linked to both `user_id` and `account_id`
- [ ] Token record stores claims: `user_id`, `account_id`, `jti` (unique token identifier)
- [ ] `fetch_api_user` plug extracts Bearer token from `Authorization` header
- [ ] `fetch_api_user` hashes the token, looks up in `user_tokens`, loads user + account
- [ ] `fetch_api_user` verifies both user is active and account membership is active; returns 401 if either check fails
- [ ] Protected API endpoints return 401 if no valid Bearer token provided
- [ ] API response includes proper `Content-Type: application/json` header
- [ ] If user has TOTP enabled, `POST /api/auth/token` also requires a `totp_code` field

**Safeguards:**
> Never store raw API tokens in the database. Always store the SHA-256 hash. The raw token is returned to the user exactly once on creation and cannot be retrieved again. This follows the same pattern phx_gen_auth uses for session tokens but adapted for API use. Tokens are account-scoped — a token issued for account A must not grant access to account B's data, even if the user belongs to both accounts.

**Notes:**
- The `fetch_api_user` plug should be in `KithWeb.Plugs.FetchApiUser`
- API pipeline in the router: `plug :fetch_api_user` (not `:fetch_current_user` which is for browser sessions)
- Consider rate limiting `POST /api/auth/token` similarly to the login endpoint (see TASK-02-15)

---

### TASK-02-14: API Token Revocation
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-02-13
**Description:**
Implement token revocation: `DELETE /api/auth/token` (authenticated with the token being revoked) deletes the token from `user_tokens`. After revocation, the token immediately stops working. The response is 204 No Content. Also provide `DELETE /api/auth/token/:token_id` for revoking specific tokens (admin or token owner only), useful for the Settings > Security UI which lists all active API tokens.

**Acceptance Criteria:**
- [ ] `DELETE /api/auth/token` revokes the token used in the current request, returns 204
- [ ] Subsequent requests with the revoked token return 401
- [ ] Token deletion is immediate (no caching of valid tokens)
- [ ] Settings > Security can list active API tokens (masked, showing creation date and last used)

**Safeguards:**
> Token revocation must be immediate. Do not cache valid tokens in ETS or any in-memory store without cache invalidation on revocation. If caching is added later, revocation must bust the cache.

**Notes:**
- Token scoping: tokens are per-user, and the user's `account_id` is used for all data scoping in API requests
- Consider adding a `last_used_at` column to `user_tokens` for API tokens (update on each authenticated request, but debounced to avoid write amplification — e.g., update at most once per minute)

---

### TASK-02-15: Per-IP Rate Limiting
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-11
**Description:**
Implement per-IP rate limiting using `hammer` via a `KithWeb.RateLimiter` plug. Apply to authentication endpoints with the following per-endpoint limits:

| Endpoint | Limit | Key |
|---|---|---|
| `POST /users/log_in` | 10 req/min per IP | IP |
| `POST /users/totp/verify` | 5 req/min per user | user_id |
| `POST /users/password/reset` | 3 req/min per IP | IP |
| `POST /api/auth/token` | 20 req/min per IP | IP |

Login (`POST /users/log_in`): lockout for 15 minutes after limit exceeded. When any rate limit is exceeded, return HTTP 429 Too Many Requests with a `Retry-After` header (seconds until the limit resets) and an RFC 7807 error body. The plug should be configurable with different limits per route.

**Acceptance Criteria:**
- [ ] `KithWeb.RateLimiter` plug implemented with configurable rate limits
- [ ] `POST /users/log_in`: 10 req/min per IP; lockout 15 minutes on exceed
- [ ] `POST /users/totp/verify`: 5 req/min per user (key: authenticated user_id, not IP)
- [ ] `POST /users/password/reset`: 3 req/min per IP
- [ ] `POST /api/auth/token`: 20 req/min per IP
- [ ] Exceeded limit returns 429 with `Retry-After` header
- [ ] Error response body uses RFC 7807 format: `{type, title, status, detail}`
- [ ] Rate limiter uses the client's real IP (respects `X-Forwarded-For` from Caddy/proxy)
- [ ] Rate limiting works with both ETS and Redis backends (based on `RATE_LIMIT_BACKEND` env var)

**Safeguards:**
> Ensure the rate limiter uses the real client IP, not the proxy IP. Phoenix's `RemoteIp` plug or a custom `Plug.Conn` extraction must be configured to trust the Caddy proxy. Without this, all requests appear to come from the same IP (the reverse proxy), making rate limiting ineffective. The TOTP verify limit is keyed by `user_id` (not IP) because an attacker controlling multiple IPs could otherwise bypass a per-IP limit to brute-force a specific user's TOTP.

**Notes:**
- `hammer` API: `Hammer.check_rate("login:#{ip}", 60_000, 10)` returns `{:allow, count}` or `{:deny, limit}`
- The plug should accept options: `plug KithWeb.RateLimiter, limit: 10, period: 60_000, lockout: 900_000`
- Apply the plug in the router pipeline or directly on route groups

---

### TASK-02-16: Per-Account API Rate Limiting
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-02-13, TASK-02-15
**Description:**
Implement per-account rate limiting for API requests: 1000 requests per hour per account. The rate limit key is the `account_id` extracted from the authenticated user's token. When exceeded, return HTTP 429 with a `Retry-After` header and an RFC 7807 error body. This is separate from per-IP rate limiting (both apply). Include rate limit headers on all API responses: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`.

**Acceptance Criteria:**
- [ ] API requests are rate-limited to 1000/hour per account
- [ ] Rate limit key is `account_id` (not user_id — all users on an account share the quota)
- [ ] Exceeded limit returns 429 with `Retry-After` header and RFC 7807 body
- [ ] All API responses include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers
- [ ] Per-account and per-IP rate limits are independent (both can trigger)

**Safeguards:**
> Use `account_id` not `user_id` as the rate limit key. Per-user limits would allow abuse by creating multiple users on the same account. Per-account limits ensure fair resource sharing regardless of user count.

**Notes:**
- Implement as a separate plug `KithWeb.ApiRateLimiter` applied in the API pipeline
- `X-RateLimit-Reset` should be a Unix timestamp (seconds)
- Consider making the 1000/hour limit configurable via env var for self-hosters

---

### TASK-02-17: Session Configuration & Security
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-02-01
**Description:**
Configure session security: encrypted cookie with `signing_salt` and `encryption_salt` derived from `SECRET_KEY_BASE`, `SameSite=Strict`, `Secure` flag (HTTPS-only in production), `HttpOnly` flag. Session tokens are stored in `user_tokens` with `context: "session"` — the cookie contains only a signed reference to the token, not the token itself. The `fetch_current_user` plug reads the session token from the cookie, looks it up in `user_tokens`, and loads the user with preloaded account. Sessions have no server-side expiry by default (browser session), but the user can configure "remember me" for 60-day persistence.

**Session token rotation:** On every successful login, a fresh session token is generated and written to `user_tokens`. On logout, the token record is deleted from `user_tokens` immediately, invalidating the session server-side. This means there is no window between logout and invalidation — replaying a stolen session cookie after logout returns a 401/redirect.

**Acceptance Criteria:**
- [ ] Session cookie is encrypted, signed, HttpOnly, SameSite=Strict
- [ ] In production: `Secure` flag is set (HTTPS-only)
- [ ] Session token stored in `user_tokens` with `context: "session"`
- [ ] `fetch_current_user` plug reads session, loads user + account from `user_tokens`
- [ ] "Remember me" checkbox on login: checked = 60-day cookie; unchecked = session cookie
- [ ] Session tokens are invalidated on password change
- [ ] `max_age` on remember-me cookie is 60 days (5_184_000 seconds)
- [ ] On successful login: a new session token is generated (old token from any prior partial session is not reused)
- [ ] On logout: the session token record is deleted from `user_tokens` immediately (server-side invalidation)
- [ ] Replaying a session cookie after logout returns an unauthenticated response (redirect to login)

**Safeguards:**
> Never store user data directly in the cookie. The cookie should contain only a token reference. This ensures that session revocation (e.g., "log out all devices") actually works — deleting the token from `user_tokens` immediately invalidates the session. Do not rely solely on cookie expiry for logout — the server-side record must be deleted.

**Notes:**
- phx_gen_auth already implements most of this; review and ensure all security settings are correct
- Add `account` preload to the user query in `fetch_current_user` for tenant isolation

---

### TASK-02-18: Concurrent Session Management
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-02-17
**Description:**
Allow users to view and manage their active sessions from Settings > Security. Display a list of all active sessions showing: device/browser (parsed from User-Agent), IP address, approximate location (if geolocation enabled), "current session" indicator, and last-seen timestamp. Users can invalidate individual sessions (delete the token from `user_tokens`) or click "Log out all other devices" to invalidate all sessions except the current one. Store session metadata (IP, User-Agent) in `user_tokens` when the session is created.

**Acceptance Criteria:**
- [ ] Settings > Security shows list of active sessions
- [ ] Each session displays: device/browser, IP address, "Current session" badge, last seen
- [ ] "Revoke" button on each session (except current) invalidates that session
- [ ] "Log out all other devices" button invalidates all sessions except current
- [ ] After revoking a session, the user on that session is immediately logged out on next request
- [ ] Session metadata (IP, User-Agent) stored in `user_tokens` metadata column (JSONB)
- [ ] Last-seen timestamp updated periodically (not on every request — debounce to once per 5 minutes)

**Safeguards:**
> Do not update `last_seen_at` on every single request — this creates excessive database writes. Debounce updates to at most once per 5 minutes using a process-local cache or ETS-based timestamp check.

**Notes:**
- Add a `metadata` JSONB column to `user_tokens` for storing IP, User-Agent, and last_seen_at
- Use a simple User-Agent parser (e.g., `ua_inspector` or a lightweight regex) — no need for a full library
- The "Log out all other devices" query: `DELETE FROM user_tokens WHERE user_id = ? AND context = 'session' AND token != ?`

---

### TASK-02-19: CSRF Protection
**Priority:** High
**Effort:** XS
**Depends on:** TASK-02-01
**Description:**
Ensure CSRF protection is properly configured across the application. Phoenix provides built-in CSRF tokens via `Plug.CSRFProtection` — verify it is in the browser pipeline. Document that Alpine.js form submissions (if any — though Alpine.js should not submit forms per the scope boundary) must include the CSRF token from the `<meta>` tag. LiveView forms automatically include CSRF tokens. API endpoints (Bearer token auth) are exempt from CSRF checks.

**Acceptance Criteria:**
- [ ] `Plug.CSRFProtection` is in the browser pipeline
- [ ] All HTML forms rendered by Phoenix include CSRF tokens automatically
- [ ] LiveView form submissions include CSRF tokens (built-in behavior)
- [ ] API pipeline does not include CSRF protection (Bearer tokens are CSRF-immune)
- [ ] Documentation note: if Alpine.js ever submits a form (against scope boundary), it must include `_csrf_token` from `<meta name="csrf-token">`
- [ ] CSRF token mismatch returns 403 with a clear error page

**Safeguards:**
> Do not disable CSRF protection on any browser-facing route. The API pipeline is exempt because Bearer token authentication is not vulnerable to CSRF (the token is in the `Authorization` header, not a cookie).

**Notes:**
- This is mostly verification and documentation — Phoenix handles CSRF out of the box
- Ensure the root layout includes `<meta name="csrf-token" content={get_csrf_token()}>` for any JS that needs it

---

### TASK-02-20: Secure Headers
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-13
**Description:**
Configure security headers via `plug_content_security_policy` and additional custom plugs. CSP policy: `default-src 'self'`; `script-src 'self' 'nonce-{random}'` (nonce-based for inline scripts required by LiveView); `style-src 'self' 'unsafe-inline'` (required for Tailwind's runtime styles); `img-src 'self' data: blob:` (data URLs for QR codes, blob for image previews); `connect-src 'self' wss:` (WebSocket for LiveView); `frame-ancestors 'none'`. Additional headers: `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=()`.

**Acceptance Criteria:**
- [ ] `Content-Security-Policy` header set on all responses with the specified directives
- [ ] CSP uses nonces for inline scripts (LiveView requirement)
- [ ] `X-Frame-Options: DENY` header set
- [ ] `X-Content-Type-Options: nosniff` header set
- [ ] `Referrer-Policy: strict-origin-when-cross-origin` header set
- [ ] `Permissions-Policy` header restricts camera, microphone, geolocation
- [ ] CSP violations do not break LiveView WebSocket connections
- [ ] CSP does not block QR code data URLs (`img-src` includes `data:`)

**Safeguards:**
> LiveView requires WebSocket connections (`connect-src 'self' wss:`) and may inject inline scripts that need nonce-based CSP exceptions. Test thoroughly that LiveView works correctly with the CSP policy. An overly strict CSP will break LiveView silently. Also verify that `style-src 'unsafe-inline'` is present — Tailwind CSS may use inline styles.

**Notes:**
- `plug_content_security_policy` generates nonces automatically; pass the nonce to the root layout
- The `frame-ancestors 'none'` CSP directive supersedes `X-Frame-Options: DENY` in modern browsers, but include both for backwards compatibility
- Test the CSP in dev mode — LiveView dev tools (e.g., live reload) may need additional CSP exceptions in dev only

---

### TASK-02-21: Authorization Foundation (Kith.Policy)
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-02-01
**Description:**
Implement the `Kith.Policy` module with a single public function `can?(user, action, resource)` that returns `true` or `false`. Define all v1 action atoms and their role mappings. Roles: `admin` (all actions), `editor` (all except admin-only actions), `viewer` (only view actions and own settings). The `resource` parameter is used for ownership checks (e.g., a viewer can update their own user settings but not other users'). Integrate `Kith.Policy.can?/3` into LiveView `mount/3` and `handle_event/3` for browser authorization, and into controller actions for API authorization. Unauthorized access returns 403 in the API or redirects to a 403 page in the browser with a message explaining the role limitation.

**Acceptance Criteria:**
- [ ] `Kith.Policy.can?(user, action, resource)` function implemented
- [ ] All v1 action atoms defined — **Contacts:** `:create_contact`, `:edit_contact`, `:delete_contact`, `:archive_contact`, `:restore_contact` (admin), `:permanent_delete_contact` (admin), `:view_contact`, `:merge_contacts` (editor+); **Notes:** `:create_note`, `:edit_note`, `:delete_note`, `:view_note`; **Activities:** `:create_activity`, `:edit_activity`, `:delete_activity`; **Calls:** `:create_call`, `:edit_call`, `:delete_call`; **Life Events:** `:create_life_event`, `:edit_life_event`, `:delete_life_event`; **Files:** `:upload_photo`, `:delete_photo`, `:upload_document`, `:delete_document`; **Addresses:** `:create_address`, `:edit_address`, `:delete_address`; **Contact Fields:** `:create_contact_field`, `:edit_contact_field`, `:delete_contact_field`; **Relationships:** `:create_relationship`, `:delete_relationship`; **Bulk:** `:bulk_tag`, `:bulk_archive`, `:bulk_delete` (editor+); **Account:** `:manage_users` (admin), `:manage_account` (admin), `:export_data`, `:import_data`, `:trigger_immich_sync`, `:view_audit_log` (admin), `:manage_tags`, `:manage_genders`, `:manage_relationship_types`, `:manage_contact_field_types`
- [ ] Account-level admin actions fully defined (resource is the `%Account{}` struct):
  - `can?(user, :invite_member, account)` — admin only
  - `can?(user, :remove_member, account)` — admin only
  - `can?(user, :change_member_role, account)` — admin only
  - `can?(user, :delete_account, account)` — admin only
  - `can?(user, :reset_account, account)` — admin only
  - `can?(user, :manage_integrations, account)` — admin only
  - `can?(user, :export_data, account)` — admin and editor
  - `can?(user, :view_audit_log, account)` — admin only
- [ ] Admin role: all actions permitted
- [ ] Editor role: all actions except `:restore_contact`, `:permanent_delete_contact`, `:manage_users`, `:manage_account`, `:view_audit_log`, `:invite_member`, `:remove_member`, `:change_member_role`, `:delete_account`, `:reset_account`, `:manage_integrations`
- [ ] Viewer role: only `view_*` actions and updating own user settings
- [ ] 403 error page for browser with explanation: "Your role (viewer) does not have permission to perform this action. Contact your account administrator."
- [ ] 403 RFC 7807 response for API
- [ ] `authorize!/3` convenience function that raises `Kith.NotAuthorizedError` (caught by error handler)
- [ ] Comprehensive unit tests for all role/action combinations

**Safeguards:**
> Authorization checks must happen in the context/controller layer, not only in templates. Hiding a button in the UI is not authorization — the server must reject unauthorized actions. Every context function that mutates data should call `Kith.Policy.can?/3` or the caller (controller/LiveView) must check before calling.

**Notes:**
- Define actions as module attribute lists for easy auditing: `@admin_only_actions [:restore_contact, :permanent_delete_contact, :manage_users, :manage_account, :view_audit_log, :invite_member, :remove_member, :change_member_role, :delete_account, :reset_account, :manage_integrations]`, `@editor_plus_actions [:merge_contacts, :bulk_tag, :bulk_archive, :bulk_delete, :export_data, :import_data, :trigger_immich_sync, ...]`
- The `resource` parameter can be `nil` for actions that don't need ownership checks, or a struct like `%User{}` for ownership checks (e.g., viewer can update own `%User{}`)
- Consider a `Kith.Policy.authorize!/3` that raises, and a `Kith.Policy.can?/3` that returns boolean — LiveViews use `can?/3` for template conditionals, controllers use `authorize!/3` for action guards

---

### TASK-02-22: Bootstrap Kith.AuditLog Context
**Priority:** High
**Effort:** M
**Depends on:** TASK-02-01
**Description:**
Bootstrap the `Kith.AuditLog` context in Phase 02 because auth events are the first domain events that must be audited. The audit log is an **append-only** store — no update or delete operations are ever performed on it. All writes go through an Oban worker (fire-and-forget) so audit logging never blocks a request.

Create the `audit_logs` table with the following schema:

| Column | Type | Constraints |
|---|---|---|
| `id` | bigserial | PRIMARY KEY |
| `account_id` | bigint | NOT NULL, FK → accounts.id ON DELETE CASCADE |
| `actor_id` | bigint | NULL, FK → users.id ON DELETE SET NULL (null = system event) |
| `action` | varchar | NOT NULL — e.g. `"auth.login"`, `"auth.mfa_failed"`, `"contact.created"` |
| `resource_type` | varchar | NULL — e.g. `"Contact"`, `"User"` |
| `resource_id` | bigint | NULL |
| `metadata` | jsonb | NOT NULL DEFAULT `'{}'` |
| `ip_address` | inet | NULL |
| `inserted_at` | timestamptz | NOT NULL DEFAULT now() |

**No `updated_at` column** — audit_logs is insert-only by design.

**Acceptance Criteria:**
- [ ] Migration creates the `audit_logs` table with all columns and constraints above
- [ ] `Kith.AuditLog.Entry` schema defined (no changeset — insert-only via raw insert)
- [ ] `Kith.AuditLog.log/3` function signature: `log(scope, action, opts \\ [])` where `scope` is a map or struct carrying `account_id`, `actor_id`, and optional `ip`
  - `opts`: `resource: struct` (resource_type and resource_id extracted automatically), `metadata: map`, `ip: string`
  - Inserts asynchronously by enqueuing an `AuditLogWorker` Oban job (fire-and-forget — the caller does not wait for the insert)
- [ ] `Kith.AuditLog.AuditLogWorker` Oban worker (queue: `:default`) performs the actual `Repo.insert!/1`
- [ ] Auth events wired up to `Kith.AuditLog.log/3`:
  - Login success: `action: "auth.login"`
  - Login failure (bad password): `action: "auth.login_failed"`
  - MFA success: `action: "auth.mfa_success"`
  - MFA failure: `action: "auth.mfa_failed"`
  - OAuth login: `action: "auth.oauth_login"`, `metadata: %{provider: provider}`
  - Password reset requested: `action: "auth.password_reset_requested"`
  - API token created: `action: "auth.api_token_created"`
  - API token revoked: `action: "auth.api_token_revoked"`
- [ ] `audit_logs` table has an index on `(account_id, inserted_at DESC)` for efficient log viewing

**Safeguards:**
> The audit log must never block a user-facing request. All writes must go through the Oban job. Do not call `Repo.insert` directly from a controller or LiveView action — always go through `Kith.AuditLog.log/3`. The table must have no update or delete operations — enforce this by having no `update_*` or `delete_*` functions in the `Kith.AuditLog` module.

**Notes:**
- `resource_type` should be derived from the struct module name: `resource.__struct__ |> Module.split() |> List.last()`
- `resource_id` assumes the struct has an `id` field; use `Map.get(resource, :id)` safely
- The `ip_address` column uses PostgreSQL `inet` type; pass as a string from `conn.remote_ip` formatted with `:inet.ntoa/1`
- Future phases (contacts, notes, activities) will call `Kith.AuditLog.log/3` for their own domain events; the infrastructure built here is reused across all phases

---

### TASK-02-NEW-A: User Active Status
**Priority:** High
**Effort:** S
**Depends on:** TASK-02-01, TASK-02-13
**Description:**
Define a `users.is_active boolean NOT NULL DEFAULT true` column to support user deactivation by admins. The `Accounts` context exposes `deactivate_user/2` and `reactivate_user/2`, both admin-only operations. The `fetch_api_user/1` and `fetch_current_user/1` plugs must check `is_active = true` before granting access. Deactivated users cannot log in, initiate a password reset, or authenticate via API tokens.

> **Cross-reference:** The `is_active` column must be included in the Phase 03 migration that creates the `users` table. Add a note in the Phase 03 plan referencing this requirement.

**Acceptance Criteria:**
- [ ] `users.is_active` column exists as `boolean NOT NULL DEFAULT true`
- [ ] `Accounts.deactivate_user/2` sets `is_active = false`; admin-only (checked via `Kith.Policy.can?/3`)
- [ ] `Accounts.reactivate_user/2` sets `is_active = true`; admin-only
- [ ] Login attempt by an inactive user does not return 401 — instead shows an "account deactivated" flash message on the login form
- [ ] `fetch_api_user/1` returns `403 Forbidden` with an RFC 7807 body when the user is inactive
- [ ] `fetch_current_user/1` treats inactive users as unauthenticated (redirects to login)
- [ ] Password reset flow rejects the email submission for inactive users (no reset token is generated; response is still the generic "if an account exists…" message to avoid enumeration)
- [ ] Tests: deactivate user → login fails with deactivated flash; reactivate user → login succeeds

**Safeguards:**
> The deactivated-user login response must not leak whether the email exists. Show the "account deactivated" message only after verifying the password — identical timing to a normal failed login. Do not reveal deactivation status to unauthenticated callers.

**Notes:**
- The `is_active` check in `fetch_api_user/1` must come after the token lookup so the 403 is only triggered for a valid token belonging to an inactive user (invalid tokens still return 401)
- Deactivating a user does not delete their sessions — those will fail naturally on the next request via `fetch_current_user/1`

---

### TASK-02-NEW-B: Password Change from Settings
**Priority:** High
**Effort:** S
**Depends on:** TASK-02-01, TASK-02-17
**Description:**
Implement a password change flow accessible from Settings > Security. This is distinct from the password reset flow (TASK-02-03): it requires the user to supply their current password before accepting a new one. On success, all existing sessions for the user are invalidated (except optionally the current one — implementation decision) and a "your password was changed" notification email is sent via Swoosh. The endpoint is rate-limited to 5 attempts per 15 minutes per user.

**Acceptance Criteria:**
- [ ] `Accounts.change_password/3` function with signature `change_password(user, old_password, new_password)`
- [ ] Validates `old_password` against the stored hash before accepting the change; returns an error if it does not match
- [ ] New password subject to the same validation rules as registration (min 12, max 72 characters)
- [ ] On success: all existing session tokens for the user (`context: "session"`) are deleted from `user_tokens`
- [ ] On success: a "your password was changed" email is sent via the Oban mailer queue (Swoosh)
- [ ] Rate limit: 5 attempts per 15 minutes per user (key: `user_id`); excess attempts return a user-visible error message on the Settings form
- [ ] Settings > Security page contains the password change form with fields: current password, new password, confirm new password
- [ ] After successful change, user is redirected to login (all sessions invalidated, including current)

**Safeguards:**
> Always validate the old password before making any change. Never allow a password change based solely on being logged in — this would allow session hijackers to lock out the legitimate user. The rate limit must key on `user_id`, not IP, to prevent distributed attempts against a specific account.

**Notes:**
- The "confirm new password" field is UI-only validation; the context function only takes `old_password` and `new_password`
- The notification email should include the timestamp and approximate location (IP) of the change so the user can identify unauthorized changes
- Add an audit log entry: `action: "auth.password_changed"` via `Kith.AuditLog.log/3`

---

## E2E Product Tests

### TEST-02-01: Full Registration and Email Verification Flow
**Type:** Browser (Playwright)
**Covers:** TASK-02-01, TASK-02-02, TASK-02-04

**Scenario:**
Verify that a new user can register, receive a verification email, click the verification link, and access the application. This test runs with `SIGNUP_DOUBLE_OPTIN=true`.

**Steps:**
1. Navigate to `/auth/register`
2. Fill in email and password (minimum 12 characters)
3. Submit the registration form
4. Verify redirect to "Check your email" page
5. Retrieve the verification email from Mailpit API (`GET http://localhost:8025/api/v1/messages`)
6. Extract the verification link from the email body
7. Navigate to the verification link
8. Verify redirect to dashboard and user is logged in

**Expected Outcome:**
User sees the dashboard after clicking the verification link. The "Check your email" page is no longer shown on subsequent logins.

---

### TEST-02-02: Login with Wrong Password
**Type:** Browser (Playwright)
**Covers:** TASK-02-01, TASK-02-03

**Scenario:**
Verify that login with an incorrect password fails gracefully and does not reveal whether the email exists in the system.

**Steps:**
1. Navigate to `/auth/login`
2. Enter a valid registered email and an incorrect password
3. Submit the login form
4. Observe the error message
5. Clear the form, enter a non-existent email and any password
6. Submit the login form
7. Observe the error message

**Expected Outcome:**
Both attempts show the same generic error message (e.g., "Invalid email or password"). The error message does not differentiate between "email not found" and "wrong password."

---

### TEST-02-03: TOTP Setup — Scan QR and Enable
**Type:** Browser (Playwright)
**Covers:** TASK-02-05, TASK-02-07

**Scenario:**
Verify that a logged-in user can enable TOTP two-factor authentication by scanning a QR code (or using the manual secret) and confirming with a valid code.

**Steps:**
1. Log in as a registered user
2. Navigate to Settings > Security
3. Click "Enable Two-Factor Authentication"
4. Extract the TOTP secret from the manual entry field on the page
5. Generate a valid TOTP code using the secret (use a TOTP library or compute from the secret)
6. Enter the 6-digit code in the confirmation field
7. Submit the confirmation
8. Verify that recovery codes are displayed
9. Verify that Settings > Security now shows "Two-Factor Authentication: Enabled"

**Expected Outcome:**
TOTP is enabled. 10 recovery codes are displayed with the warning "Store these somewhere safe." Settings page shows 2FA as enabled.

---

### TEST-02-04: TOTP Login — Correct Code
**Type:** Browser (Playwright)
**Covers:** TASK-02-06

**Scenario:**
Verify that a user with TOTP enabled is redirected to the TOTP challenge after entering correct password, and can log in with a valid TOTP code.

**Steps:**
1. Ensure a test user has TOTP enabled (from TEST-02-03 setup)
2. Navigate to `/auth/login`
3. Enter correct email and password
4. Submit the login form
5. Verify redirect to `/auth/two_factor`
6. Generate a valid TOTP code from the user's secret
7. Enter the 6-digit code
8. Submit the TOTP challenge form

**Expected Outcome:**
User is redirected to the dashboard and is fully logged in.

---

### TEST-02-05: TOTP Login — Wrong Code
**Type:** Browser (Playwright)
**Covers:** TASK-02-06

**Scenario:**
Verify that entering an incorrect TOTP code does not grant access.

**Steps:**
1. Navigate to `/auth/login` with a TOTP-enabled account
2. Enter correct email and password
3. On the TOTP challenge page, enter `000000` (invalid code)
4. Submit the TOTP challenge form

**Expected Outcome:**
Error message displayed: "Invalid two-factor code." User remains on the TOTP challenge page and is not logged in.

---

### TEST-02-06: Recovery Code Login
**Type:** Browser (Playwright)
**Covers:** TASK-02-07

**Scenario:**
Verify that a recovery code can be used in place of a TOTP code, and that used codes cannot be reused.

**Steps:**
1. Navigate to `/auth/login` with a TOTP-enabled account
2. Enter correct email and password
3. On the TOTP challenge page, click "Use recovery code"
4. Enter one of the previously saved recovery codes
5. Submit the recovery code form
6. Verify successful login and redirect to dashboard
7. Log out
8. Repeat login with the same recovery code

**Expected Outcome:**
First login with the recovery code succeeds. Second attempt with the same code fails with an error message indicating the code has already been used or is invalid.

---

### TEST-02-07: WebAuthn Registration
**Type:** API (HTTP)
**Covers:** TASK-02-09

**Scenario:**
Verify the WebAuthn credential registration flow via API calls. Since Playwright's WebAuthn virtual authenticator support is limited, test the server-side challenge/complete flow directly.

**Steps:**
1. Authenticate as a logged-in user (obtain session cookie)
2. `POST /auth/webauthn/register/challenge` — receive challenge JSON
3. Construct a mock attestation response matching the challenge (using a test helper or virtual authenticator library)
4. `POST /auth/webauthn/register/complete` with the attestation response
5. Verify the credential appears in the user's registered credentials list via `GET` Settings > Security

**Expected Outcome:**
The registration challenge is returned with valid `publicKey` options. After completing registration, the credential is stored and visible in the user's security settings.

---

### TEST-02-08: OAuth Login via GitHub
**Type:** Browser (Playwright)
**Covers:** TASK-02-11

**Scenario:**
Verify the OAuth login flow with GitHub. Since we cannot interact with the real GitHub OAuth page in tests, mock the callback endpoint with a valid state and authorization code.

**Steps:**
1. Navigate to `/auth/github` and capture the redirect URL (verify it includes `code_challenge` for PKCE)
2. Simulate the callback: `GET /auth/github/callback?code=mock_code&state=valid_state` (using a test mock that intercepts the token exchange)
3. Verify that a new user and account are created
4. Verify the user is logged in and redirected to the dashboard
5. Check that a `UserIdentity` record exists for the GitHub provider

**Expected Outcome:**
User is logged in via GitHub OAuth. A new account is created. The UserIdentity record links the GitHub UID to the Kith user.

---

### TEST-02-09: API Bearer Token Lifecycle
**Type:** API (HTTP)
**Covers:** TASK-02-13, TASK-02-14

**Scenario:**
Verify the full API bearer token lifecycle: creation, use, and revocation.

**Steps:**
1. `POST /api/auth/token` with `{email: "test@example.com", password: "validpassword"}` — expect 201 with `{token, expires_at}`
2. `GET /api/contacts` with `Authorization: Bearer <token>` — expect 200 (or empty list)
3. `GET /api/contacts` without Authorization header — expect 401
4. `DELETE /api/auth/token` with `Authorization: Bearer <token>` — expect 204
5. `GET /api/contacts` with the revoked token — expect 401

**Expected Outcome:**
Token is created, works for authenticated requests, and stops working immediately after revocation.

---

### TEST-02-10: Rate Limiting on Login
**Type:** API (HTTP)
**Covers:** TASK-02-15

**Scenario:**
Verify that rapid login attempts trigger rate limiting and return a 429 response with a `Retry-After` header.

**Steps:**
1. Send 10 `POST /auth/login` requests in rapid succession with incorrect credentials (all from the same IP)
2. Send an 11th `POST /auth/login` request
3. Check the response status code and headers

**Expected Outcome:**
The 11th request returns HTTP 429 Too Many Requests. The response includes a `Retry-After` header with the number of seconds until the rate limit resets. The response body is an RFC 7807 error: `{type: "...", title: "Too Many Requests", status: 429, detail: "Rate limit exceeded. Try again in X seconds."}`.

---

### TEST-02-11: Session Management — Invalidate Other Session
**Type:** Browser (Playwright)
**Covers:** TASK-02-18

**Scenario:**
Verify that a user can see multiple active sessions and invalidate one, making it immediately invalid.

**Steps:**
1. Log in as user A in Browser Context 1 (Session 1)
2. Log in as user A in Browser Context 2 (Session 2) — a second browser context with independent cookies
3. In Session 1, navigate to Settings > Security > Active Sessions
4. Verify two sessions are listed
5. Click "Revoke" on the session that is NOT the current one
6. In Session 2, navigate to any protected page

**Expected Outcome:**
Session 2 is logged out — the user is redirected to the login page. Session 1 remains active.

---

### TEST-02-12: Viewer Role Cannot Edit Contact
**Type:** Browser (Playwright)
**Covers:** TASK-02-21

**Scenario:**
Verify that a user with the `viewer` role cannot access contact editing functionality.

**Steps:**
1. Log in as a user with role `viewer`
2. Navigate to a contact's profile page — verify it loads successfully (viewers can view)
3. Attempt to navigate to the contact's edit page (`/contacts/:id/edit`)
4. Observe the response

**Expected Outcome:**
The viewer is shown a 403 error page with the message: "Your role (viewer) does not have permission to perform this action. Contact your account administrator." The edit page is not rendered.

---

### TEST-02-13: Admin Can Access User Management
**Type:** Browser (Playwright)
**Covers:** TASK-02-21

**Scenario:**
Verify that an admin user can access the user management settings page.

**Steps:**
1. Log in as a user with role `admin`
2. Navigate to Settings > Users & Invitations
3. Verify the page loads and displays the list of users on the account

**Expected Outcome:**
The admin sees the user management page with a list of account users, their roles, and options to invite new users or change roles.

---

### TEST-02-14: Editor Cannot Access User Management
**Type:** Browser (Playwright)
**Covers:** TASK-02-21

**Scenario:**
Verify that an editor user cannot access the user management settings page.

**Steps:**
1. Log in as a user with role `editor`
2. Navigate to Settings > Users & Invitations (direct URL: `/settings/users`)
3. Observe the response

**Expected Outcome:**
The editor is shown a 403 error page or is redirected away from the user management page. The page content is not rendered.

---

## Phase Safeguards

- **Never store secrets in plaintext.** TOTP secrets, OAuth tokens, and API tokens must be encrypted or hashed before database storage. Use application-level encryption (AES-256-GCM via `Cloak` or a custom Ecto type) for reversible secrets and bcrypt/SHA-256 for irreversible ones.
- **Never reveal user existence.** Login failure messages, password reset responses, and registration error messages must not indicate whether an email address is registered. Use identical response timing (constant-time comparison) to prevent timing attacks.
- **Rate limiting must use real client IPs.** Configure `RemoteIp` plug to trust the Caddy reverse proxy. Without this, all requests appear from the same proxy IP, defeating rate limiting entirely.
- **Authorization is server-side, not UI-only.** Hiding a button for a viewer role is a UX courtesy, not a security measure. Every controller action and LiveView event handler must verify authorization via `Kith.Policy`.
- **Test TOTP with time drift.** The TOTP validation window of 1 (current + previous 30-second period) must be explicitly tested. Authenticator apps can have slight clock drift, and rejecting valid codes frustrates users.
- **WebAuthn Relying Party ID must match the hostname.** A mismatch between `rp.id` and the browser's origin will cause silent failures in the WebAuthn API. This is the most common WebAuthn integration bug.

## Phase Notes

- **Migration ordering:** The `accounts` table must be created before `users` (FK dependency). The `user_tokens` migration from phx_gen_auth must be modified to reference the customized `users` table. `webauthn_credentials`, `user_identities`, and `user_recovery_codes` are new tables created in this phase.
- **Encryption key rotation:** The encryption key for TOTP secrets and OAuth tokens is derived from `SECRET_KEY_BASE`. Plan for key rotation support in the encryption module (support decrypting with old keys, encrypting with new keys). This is a v1.5 enhancement but the data model should not preclude it.
- **Dependency on Phase 01:** This phase requires Hammer (rate limiting), Swoosh (email), Oban (async jobs), and the Phoenix endpoint with CSP headers to be configured. Do not start TASK-02-05 (TOTP) until `eqrcode` is added to `mix.exs`.
- **The `me_contact_id` FK on users:** This references the `contacts` table which does not exist until Phase 04. Add this column as nullable with no FK constraint in the Phase 02 migration, and add the FK constraint in the Phase 04 migration. Alternatively, defer this column entirely to Phase 04.
- **Session metadata for concurrent session management (TASK-02-18):** The `user_tokens` table needs a `metadata` JSONB column. Add this in the same migration that creates `user_tokens`, not as a separate migration.
