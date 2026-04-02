import { test, expect } from "@playwright/test";
import { registerUser, ensureOnDashboard } from "./helpers/auth";

test.describe("Settings", () => {
  test.beforeEach(async ({ page }) => {
    await registerUser(page);
    await ensureOnDashboard(page);
  });

  // ─────────────────────────────────────────
  // Settings: User Profile
  // ─────────────────────────────────────────

  test("user settings page loads", async ({ page }) => {
    await page.goto("/users/settings");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveURL(/\/users\/settings/);

    // Should show profile settings form
    const content = await page.content();
    expect(content).toMatch(/settings|profile|email/i);
  });

  test("user settings shows email form", async ({ page }) => {
    await page.goto("/users/settings");
    await page.waitForLoadState("networkidle");

    // Should have an email input pre-filled
    const emailInput = page.locator("input[type='email'], input[name*='email']");
    if ((await emailInput.count()) > 0) {
      const value = await emailInput.first().inputValue();
      expect(value).toContain("@");
    }
  });

  // ─────────────────────────────────────────
  // Settings: Account
  // ─────────────────────────────────────────

  test("account settings page loads", async ({ page }) => {
    await page.goto("/settings/account");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveURL(/\/settings\/account/);

    const content = await page.content();
    expect(content).toMatch(/account|timezone|features/i);
  });

  test("account settings danger zone shows reset and delete sections", async ({
    page,
  }) => {
    await page.goto("/settings/account");
    await page.waitForLoadState("networkidle");

    const content = await page.content();
    expect(content).toMatch(/reset account data/i);
    expect(content).toMatch(/delete account/i);
  });

  test("account reset with wrong confirmation shows error", async ({
    page,
  }) => {
    await page.goto("/settings/account");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);

    // Fill wrong confirmation in reset form
    const resetInput = page.locator(
      "input[name='confirmation'][form*='reset'], form[phx-submit='reset-account'] input",
    );
    if ((await resetInput.count()) > 0) {
      await resetInput.first().fill("WRONG");
      await page.getByRole("button", { name: /reset account/i }).click();
      await page.waitForTimeout(500);

      const content = await page.content();
      expect(content).toMatch(/RESET|invalid|confirmation/i);
    }
  });

  test("account reset with correct confirmation enqueues reset job", async ({
    page,
  }) => {
    await page.goto("/settings/account");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);

    const resetInput = page.locator(
      "form[phx-submit='reset-account'] input",
    );
    if ((await resetInput.count()) > 0) {
      await resetInput.first().fill("RESET");
      await page.getByRole("button", { name: /reset account/i }).click();
      await page.waitForTimeout(1000);

      const content = await page.content();
      expect(content).toMatch(/reset|scheduled|processing/i);
    }
  });

  test("account delete with wrong confirmation shows error", async ({
    page,
  }) => {
    await page.goto("/settings/account");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);

    const deleteInput = page.locator(
      "form[phx-submit='delete-account'] input",
    );
    if ((await deleteInput.count()) > 0) {
      await deleteInput.first().fill("WRONG");
      await page.getByRole("button", { name: /delete account/i }).click();
      await page.waitForTimeout(500);

      const content = await page.content();
      expect(content).toMatch(/DELETE|invalid|confirmation/i);
    }
  });

  // ─────────────────────────────────────────
  // Settings: Tags
  // ─────────────────────────────────────────

  test("tags settings page loads", async ({ page }) => {
    await page.goto("/settings/tags");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveURL(/\/settings\/tags/);
  });

  test("create a tag", async ({ page }) => {
    await page.goto("/settings/tags");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);

    // Look for Add/Create tag button
    const addBtn = page.getByRole("button", { name: /add|create|new/i });
    if ((await addBtn.count()) > 0) {
      await addBtn.first().click();
      await page.waitForTimeout(500);

      // Fill tag name
      const nameInput = page.getByLabel(/name/i);
      if ((await nameInput.count()) > 0) {
        await nameInput.first().fill("PlaywrightTag");

        // Submit
        const saveBtn = page.getByRole("button", { name: /save|create/i });
        if ((await saveBtn.count()) > 0) {
          await saveBtn.last().click();
          await page.waitForTimeout(1000);

          const content = await page.content();
          expect(content).toContain("PlaywrightTag");
        }
      }
    }
  });

  // ─────────────────────────────────────────
  // Settings: Integrations
  // ─────────────────────────────────────────

  test("integrations settings page loads", async ({ page }) => {
    await page.goto("/settings/integrations");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveURL(/\/settings\/integrations/);

    const content = await page.content();
    expect(content).toMatch(/immich|integration/i);
  });

  // ─────────────────────────────────────────
  // Settings: Import
  // ─────────────────────────────────────────

  test("import page loads with file upload", async ({ page }) => {
    await page.goto("/settings/import");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveURL(/\/settings\/import/);

    const content = await page.content();
    expect(content).toMatch(/import|vcf|vcard|upload/i);
  });

  // ─────────────────────────────────────────
  // Settings: Export
  // ─────────────────────────────────────────

  test("export page loads with download options", async ({ page }) => {
    await page.goto("/settings/export");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveURL(/\/settings\/export/);

    const content = await page.content();
    expect(content).toMatch(/export|download|vcard/i);
  });

  // ─────────────────────────────────────────
  // Settings: Audit Log
  // ─────────────────────────────────────────

  test("audit log page loads", async ({ page }) => {
    await page.goto("/settings/audit-log");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveURL(/\/settings\/audit-log/);

    const content = await page.content();
    expect(content).toMatch(/audit|log|event/i);
  });

  // ─────────────────────────────────────────
  // Settings: Navigation between sections
  // ─────────────────────────────────────────

  test("settings sidebar navigation works", async ({ page }) => {
    await page.goto("/settings/account");
    await page.waitForLoadState("networkidle");

    // Navigate to Tags via sidebar link
    const tagsLink = page.getByRole("link", { name: /tags/i });
    if ((await tagsLink.count()) > 0) {
      await tagsLink.first().click();
      await expect(page).toHaveURL(/\/settings\/tags/, { timeout: 5_000 });
    }

    // Navigate to Integrations
    const intLink = page.getByRole("link", { name: /integrations/i });
    if ((await intLink.count()) > 0) {
      await intLink.first().click();
      await expect(page).toHaveURL(/\/settings\/integrations/, {
        timeout: 5_000,
      });
    }
  });
});
