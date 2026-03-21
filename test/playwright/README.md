# Playwright E2E Tests

Browser-based end-to-end tests for Kith. These tests run against a live Phoenix
server using real Chromium, covering authentication flows, contact management,
settings, and integrations.

## Prerequisites

```bash
# Install Playwright browsers (one-time)
npx playwright install chromium
```

## Running Tests

```bash
# 1. Start the Phoenix server (dev or test mode)
mix phx.server
# or: MIX_ENV=test mix phx.server

# 2. (Optional) Seed test data for pre-populated tests
MIX_ENV=test mix run test/playwright/seed.exs

# 3. Run the E2E test suite
npx playwright test --project=e2e

# Run a single spec file
npx playwright test --project=e2e test/playwright/auth.spec.ts

# Run with headed browser (visible)
npx playwright test --project=e2e --headed

# Run the separate smoke tests (e2e/ directory)
npx playwright test --project=smoke
```

## Test Data Setup

Playwright tests run outside the Elixir test harness — they hit the running
application over HTTP. Most tests self-provision by registering a fresh user
via the registration form (see `helpers/auth.ts`). For tests that need
pre-existing data:

- **Seed script** — `MIX_ENV=test mix run test/playwright/seed.exs`
  Creates a known user (`playwright@test.local` / `ValidP@ssword123!`)
  with sample contacts, notes, and reference data.

## Architecture

Tests are self-isolating: each test registers a unique user with a timestamped
email address, so tests can run in parallel without cross-contamination. The
shared `helpers/auth.ts` module provides `registerUser()`, `loginUser()`, and
`logoutUser()` helpers.

## Directory Structure

```
test/playwright/
├── README.md              # This file
├── helpers/
│   └── auth.ts            # Shared auth helpers (register, login, logout)
├── auth.spec.ts           # Authentication flows (21 tests)
├── contacts.spec.ts       # Contact CRUD, search, notes (10 tests)
├── reminders.spec.ts      # Reminder management (3 tests)
├── settings.spec.ts       # Account/user settings, tags (10 tests)
├── immich.spec.ts         # Immich photo integration (4 tests)
├── import-export.spec.ts  # vCard import/export (4 tests)
├── screenshots/           # Screenshot baselines for visual regression
└── seed.exs               # Elixir script to seed test data
```

## Conventions

- One `.spec.ts` file per feature area
- Tests use resilient selectors: `getByRole`, `getByLabel`, `getByPlaceholder`
- Optional UI elements are guarded with `count() > 0` checks to avoid
  flakiness when features are toggled off
- Each `beforeEach` registers a fresh user to avoid state leakage

## Relationship to Other Test Suites

| Suite | Runner | Scope | Isolation |
|-------|--------|-------|-----------|
| ExUnit (`mix test`) | ExUnit | Unit + integration | Ecto sandbox |
| Smoke (`e2e/`) | Playwright | Unauthenticated pages | None (stateless) |
| **E2E** (`test/playwright/`) | Playwright | Full user flows | Per-user registration |
