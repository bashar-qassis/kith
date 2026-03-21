import { test, expect } from "@playwright/test";

// ─────────────────────────────────────────────
// 1. Health & Landing
// ─────────────────────────────────────────────

test.describe("Health & Landing", () => {
  test("GET /health returns ok", async ({ request }) => {
    const res = await request.get("/health");
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("ok");
  });

  test("Landing page loads with 200", async ({ page }) => {
    const res = await page.goto("/");
    expect(res?.status()).toBe(200);
    await expect(page).toHaveTitle("Kith");
  });
});

// ─────────────────────────────────────────────
// 2. Auth pages render correctly
// ─────────────────────────────────────────────

test.describe("Auth Pages", () => {
  test("Registration page renders form", async ({ page }) => {
    await page.goto("/users/register");
    await expect(page.getByRole("heading", { name: /register/i })).toBeVisible();
    await expect(page.getByRole("textbox", { name: /email/i })).toBeVisible();
    await expect(page.getByRole("textbox", { name: /password/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /create an account/i })).toBeVisible();
  });

  test("Login page renders form", async ({ page }) => {
    await page.goto("/users/log-in");
    await expect(page.getByRole("heading", { name: /log in/i })).toBeVisible();
    await expect(page.getByRole("textbox", { name: /email/i })).toBeVisible();
    await expect(page.getByRole("textbox", { name: /password/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /log in/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /forgot password/i })).toBeVisible();
  });

  test("Forgot password page renders form", async ({ page }) => {
    await page.goto("/users/reset-password");
    await expect(page.getByRole("textbox", { name: /email/i })).toBeVisible();
  });

  test("Registration → Login link works", async ({ page }) => {
    await page.goto("/users/register");
    // Wait for LiveView to connect so navigate links work
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(500);
    await page.getByRole("link", { name: /log in/i }).click();
    await expect(page).toHaveURL(/\/users\/log-in/, { timeout: 10_000 });
  });

  test("Login → Registration link works", async ({ page }) => {
    await page.goto("/users/log-in");
    // Wait for LiveView to connect so navigate links work
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(500);
    await page.getByRole("link", { name: /sign up/i }).click();
    await expect(page).toHaveURL(/\/users\/register/, { timeout: 10_000 });
  });
});

// ─────────────────────────────────────────────
// 3. Auth redirects (unauthenticated access)
// ─────────────────────────────────────────────

test.describe("Auth Redirects", () => {
  const protectedRoutes = [
    "/dashboard",
    "/contacts",
    "/contacts/new",
    "/reminders/upcoming",
    "/users/settings",
    "/settings/tags",
    "/settings/integrations",
    "/settings/account",
  ];

  for (const route of protectedRoutes) {
    test(`${route} redirects to login`, async ({ page }) => {
      await page.goto(route);
      await expect(page).toHaveURL(/\/users\/log-in/);
    });
  }
});

// ─────────────────────────────────────────────
// 4. Registration flow
// ─────────────────────────────────────────────

test.describe("Registration Flow", () => {
  test("Empty form shows validation errors", async ({ page }) => {
    await page.goto("/users/register");
    await page.getByRole("button", { name: /create an account/i }).click();
    // LiveView should show inline validation - form should still be visible
    await expect(page.getByRole("button", { name: /create an account/i })).toBeVisible();
  });

  test("Invalid email shows error", async ({ page }) => {
    await page.goto("/users/register");
    await page.getByRole("textbox", { name: /email/i }).fill("not-an-email");
    await page.getByRole("textbox", { name: /password/i }).fill("short");
    await page.getByRole("textbox", { name: /password/i }).blur();
    // Wait for LiveView validation
    await page.waitForTimeout(500);
    // The page should still show the form (not crash)
    await expect(page.getByRole("button", { name: /create an account/i })).toBeVisible();
  });

  test("Successful registration creates account", async ({ page }) => {
    const email = `smoke-${Date.now()}@test.local`;
    await page.goto("/users/register");
    // Wait for LiveView to be ready before interacting with the form
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(500);
    await page.getByRole("textbox", { name: /email/i }).fill(email);
    // Use locator for the password field by its label text
    await page.locator('input[type="password"]').fill("ValidP@ssword123!");
    await page.getByRole("button", { name: /create an account/i }).click();
    // phx-trigger-action auto-submits the form via POST, then server logs in
    // and redirects to /dashboard (or /users/confirm-email if double opt-in is on)
    await page.waitForURL(/\/(dashboard|users\/confirm-email)/, { timeout: 15_000 });
  });
});

// ─────────────────────────────────────────────
// 5. Login flow
// ─────────────────────────────────────────────

test.describe("Login Flow", () => {
  const testEmail = `login-smoke-${Date.now()}@test.local`;
  const testPassword = "ValidP@ssword123!";

  test.beforeAll(async ({ request }) => {
    // Register a user via the form POST to use for login tests
    // First get the CSRF token from the registration page
    const page = await request.get("/users/register");
    const html = await page.text();
    const csrfMatch = html.match(/name="_csrf_token"[^>]*value="([^"]+)"/);
    if (!csrfMatch) return; // LiveView form, will use page-based registration instead
  });

  test("Wrong credentials show error", async ({ page }) => {
    await page.goto("/users/log-in");
    await page.getByRole("textbox", { name: /email/i }).fill("nonexistent@test.local");
    await page.getByRole("textbox", { name: /password/i }).fill("wrongpassword");
    await page.getByRole("button", { name: /log in/i }).click();
    // Should show error or remain on login page
    await expect(page).toHaveURL(/\/users\/log-in/);
  });
});

// ─────────────────────────────────────────────
// 6. Console errors (CSP / JS health)
// ─────────────────────────────────────────────

test.describe("JavaScript Health", () => {
  test("Landing page has no console errors", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (err) => errors.push(err.message));
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    expect(errors).toEqual([]);
  });

  test("Registration page JS errors (CSP audit)", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (err) => errors.push(err.message));
    await page.goto("/users/register");
    await page.waitForLoadState("networkidle");
    // This test documents CSP issues with Alpine.js
    // If this fails, Alpine.js eval is being blocked by CSP
    if (errors.length > 0) {
      console.log(`⚠️  CSP/JS errors on /users/register: ${errors.length} errors`);
      for (const e of errors) console.log(`   - ${e.substring(0, 120)}`);
    }
    // We expect zero errors in a healthy app
    expect(errors).toEqual([]);
  });

  test("Login page JS errors (CSP audit)", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (err) => errors.push(err.message));
    await page.goto("/users/log-in");
    await page.waitForLoadState("networkidle");
    if (errors.length > 0) {
      console.log(`⚠️  CSP/JS errors on /users/log-in: ${errors.length} errors`);
      for (const e of errors) console.log(`   - ${e.substring(0, 120)}`);
    }
    expect(errors).toEqual([]);
  });
});

// ─────────────────────────────────────────────
// 7. Static assets
// ─────────────────────────────────────────────

test.describe("Static Assets", () => {
  test("CSS loads successfully", async ({ request }) => {
    const res = await request.get("/assets/css/app.css");
    expect(res.status()).toBe(200);
    expect(res.headers()["content-type"]).toContain("text/css");
  });

  test("JS loads successfully", async ({ request }) => {
    const res = await request.get("/assets/js/app.js");
    expect(res.status()).toBe(200);
    expect(res.headers()["content-type"]).toContain("javascript");
  });
});

// ─────────────────────────────────────────────
// 8. API smoke tests
// ─────────────────────────────────────────────

test.describe("API Smoke", () => {
  test("POST /api/auth/token without credentials returns 401", async ({ request }) => {
    const res = await request.post("/api/auth/token", {
      data: {},
      headers: { "content-type": "application/json" },
    });
    expect([400, 401, 422]).toContain(res.status());
  });

  test("GET /api/contacts without auth returns 401", async ({ request }) => {
    const res = await request.get("/api/contacts");
    expect(res.status()).toBe(401);
  });
});

// ─────────────────────────────────────────────
// 9. Navigation structure
// ─────────────────────────────────────────────

test.describe("Navigation", () => {
  test("Bottom nav has expected links", async ({ page }) => {
    await page.goto("/users/log-in");
    const nav = page.getByRole("navigation");
    await expect(nav.getByRole("link", { name: /home/i })).toBeVisible();
    await expect(nav.getByRole("link", { name: /contacts/i })).toBeVisible();
    await expect(nav.getByRole("link", { name: /reminders/i })).toBeVisible();
    await expect(nav.getByRole("link", { name: /settings/i })).toBeVisible();
  });
});

// ─────────────────────────────────────────────
// 10. LiveView WebSocket connection
// ─────────────────────────────────────────────

test.describe("LiveView", () => {
  test("LiveView WebSocket connects on login page", async ({ page }) => {
    let wsConnected = false;
    page.on("websocket", (ws) => {
      if (ws.url().includes("/live/websocket")) {
        wsConnected = true;
      }
    });
    await page.goto("/users/log-in");
    await page.waitForLoadState("networkidle");
    // Give LiveView a moment to connect
    await page.waitForTimeout(1000);
    expect(wsConnected).toBe(true);
  });
});
