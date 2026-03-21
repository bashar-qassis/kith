# Playwright E2E Tests

Playwright tests supplement the primary Wallaby test suite with capabilities that Wallaby does not cover:

- **Visual regression testing** — screenshot comparison against baselines
- **Multi-tab flows** — session invalidation across tabs
- **Mobile viewport testing** — responsive layout verification
- **Network interception** — simulating disconnects for LiveView reconnect
- **WebAuthn simulation** — Playwright's built-in CDP WebAuthn support

## Running Tests

Playwright tests run via the Claude Code MCP plugin (`@playwright`):

```bash
# Start the app in test mode
MIX_ENV=test mix phx.server

# Run a specific spec via Playwright MCP
# (executed interactively through Claude Code)
```

Or with the Playwright CLI directly:

```bash
npx playwright test test/playwright/
```

## Test Data Setup

Playwright tests run outside the Elixir test harness — they hit the running
application over HTTP. Test data must be set up via one of:

1. **API calls** — Use the REST API with a test admin token to seed data
2. **Mix task** — `mix kith.seed_test_data` (test environment only)
3. **Factory + seed script** — `MIX_ENV=test mix run test/playwright/seed.exs`

## Conventions

- One `.spec.ts` file per feature area
- File naming: `<feature>.spec.ts` (e.g., `contacts.spec.ts`, `auth.spec.ts`)
- Screenshot baselines stored in `test/playwright/screenshots/`
- Tests are tagged by area: `@auth`, `@contacts`, `@reminders`, `@settings`

## Directory Structure

```
test/playwright/
├── README.md              # This file
├── screenshots/           # Screenshot baselines for visual regression
├── auth.spec.ts           # Authentication flows
├── contacts.spec.ts       # Contact CRUD and lifecycle
├── reminders.spec.ts      # Reminder management
├── settings.spec.ts       # Account/user settings
├── immich.spec.ts         # Immich integration
├── import-export.spec.ts  # vCard import/export
└── seed.exs               # Test data seeding script
```

## Relationship to Wallaby Tests

- **Wallaby** handles the majority of browser E2E within the ExUnit ecosystem.
  These tests run in-process with Ecto sandbox, making them fast and isolated.
- **Playwright** is for scenarios that need real browser capabilities beyond
  what Wallaby provides (visual regression, multi-tab, network interception).

## E2E Test Scenarios

All E2E test scenarios in phase plan files are written in Playwright-compatible
step-by-step format. See `docs/plan/phase-14-qa-testing.md` for the full
catalogue (TEST-14-01 through TEST-14-25).
