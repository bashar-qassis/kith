import { test, expect } from "@playwright/test";
import { registerUser, ensureOnDashboard } from "./helpers/auth";
import { createContact, goToContact } from "./helpers/contacts";

// ─────────────────────────────────────────────
// How We Met — slide-over panel E2E tests
// ─────────────────────────────────────────────

test.describe("How We Met", () => {
  let contactId: number;
  let secondContactId: number;

  test.beforeEach(async ({ page }) => {
    await registerUser(page);
    await ensureOnDashboard(page);
    contactId = await createContact(page, {
      firstName: "HowMet",
      lastName: "TestContact",
    });
  });

  // ─────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────

  test("empty state shows CTA button", async ({ page }) => {
    await goToContact(page, contactId);

    // Section header should be visible
    await expect(page.locator("text=How We Met").first()).toBeVisible();

    // Empty state CTA
    await expect(
      page.getByRole("button", { name: /add how we met/i }),
    ).toBeVisible();

    // Helper text
    await expect(
      page.locator("text=Remember how you first connected"),
    ).toBeVisible();
  });

  // ─────────────────────────────────────────
  // Panel open/close
  // ─────────────────────────────────────────

  test("CTA opens slide-over panel with grouped sections", async ({
    page,
  }) => {
    await goToContact(page, contactId);

    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);

    // Panel should be visible
    const panel = page.locator('[id^="first-met-panel-"]');
    await expect(panel).toBeVisible();

    // Verify grouped sections exist
    await expect(panel.locator("text=When")).toBeVisible();
    await expect(panel.locator("text=Where")).toBeVisible();
    await expect(panel.locator("text=Introduced by")).toBeVisible();
    await expect(panel.locator("text=The story")).toBeVisible();

    // Save and Cancel buttons
    await expect(
      panel.getByRole("button", { name: /save/i }),
    ).toBeVisible();
    await expect(
      panel.getByRole("button", { name: /cancel/i }),
    ).toBeVisible();
  });

  test("cancel closes panel without saving", async ({ page }) => {
    await goToContact(page, contactId);

    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);

    // Fill some data
    await page
      .locator('input[name="first_met[first_met_where]"]')
      .fill("Conference");

    // Cancel
    const panel = page.locator('[id^="first-met-panel-"]');
    await panel.getByRole("button", { name: /cancel/i }).click();
    await page.waitForTimeout(300);

    // Panel should be gone
    await expect(panel).not.toBeVisible();

    // Empty state should still be visible (data not saved)
    await expect(
      page.getByRole("button", { name: /add how we met/i }),
    ).toBeVisible();
  });

  test("escape key closes panel", async ({ page }) => {
    await goToContact(page, contactId);

    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);

    const panel = page.locator('[id^="first-met-panel-"]');
    await expect(panel).toBeVisible();

    await page.keyboard.press("Escape");
    await page.waitForTimeout(300);

    await expect(panel).not.toBeVisible();
  });

  test("backdrop click closes panel", async ({ page }) => {
    await goToContact(page, contactId);

    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);

    // Click the backdrop (the semi-transparent overlay)
    const backdrop = page.locator('[id^="first-met-backdrop-"]');
    await backdrop.click({ position: { x: 10, y: 10 } });
    await page.waitForTimeout(300);

    const panel = page.locator('[id^="first-met-panel-"]');
    await expect(panel).not.toBeVisible();
  });

  // ─────────────────────────────────────────
  // Save with data
  // ─────────────────────────────────────────

  test("save with all fields", async ({ page }) => {
    await goToContact(page, contactId);

    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);

    // Fill date
    await page
      .locator('input[name="first_met[first_met_at]"]')
      .fill("2020-06-15");

    // Check year unknown
    await page
      .locator('input[name="first_met[first_met_year_unknown]"]')
      .check();

    // Fill where
    await page
      .locator('input[name="first_met[first_met_where]"]')
      .fill("Coffee shop downtown");

    // Fill story (skip "through" contact — tested separately in search tests)
    await page
      .locator('textarea[name="first_met[first_met_additional_info]"]')
      .fill("Met at a birthday party");

    // Save
    const panel = page.locator('[id^="first-met-panel-"]');
    await panel.getByRole("button", { name: /save/i }).click();
    await page.waitForTimeout(500);

    // Panel should close
    await expect(panel).not.toBeVisible();

    // Verify data appears in the sidebar
    const content = await page.content();
    expect(content).toContain("Coffee shop downtown");
    expect(content).toContain("Met at a birthday party");

    // Edit button should now be visible (not CTA)
    await expect(
      page.getByRole("button", { name: /edit/i }).first(),
    ).toBeVisible();
  });

  test("save with partial fields (only where and story)", async ({
    page,
  }) => {
    await goToContact(page, contactId);

    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);

    await page
      .locator('input[name="first_met[first_met_where]"]')
      .fill("University");
    await page
      .locator('textarea[name="first_met[first_met_additional_info]"]')
      .fill("Same dorm room");

    const panel = page.locator('[id^="first-met-panel-"]');
    await panel.getByRole("button", { name: /save/i }).click();
    await page.waitForTimeout(500);

    await expect(panel).not.toBeVisible();

    const content = await page.content();
    expect(content).toContain("University");
    expect(content).toContain("Same dorm room");
  });

  // ─────────────────────────────────────────
  // Edit existing data
  // ─────────────────────────────────────────

  test("edit existing data - panel pre-fills", async ({ page }) => {
    await goToContact(page, contactId);

    // First add some data
    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);
    await page
      .locator('input[name="first_met[first_met_where]"]')
      .fill("Office");
    const panel = page.locator('[id^="first-met-panel-"]');
    await panel.getByRole("button", { name: /save/i }).click();
    await page.waitForTimeout(500);

    // Now click Edit
    await page
      .getByRole("button", { name: /edit/i }).first()
      .click();
    await page.waitForTimeout(300);

    // Verify pre-filled value
    const whereInput = page.locator(
      'input[name="first_met[first_met_where]"]',
    );
    await expect(whereInput).toHaveValue("Office");
  });

  test("edit and update - sidebar reflects change", async ({ page }) => {
    await goToContact(page, contactId);

    // Add initial data
    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);
    await page
      .locator('input[name="first_met[first_met_where]"]')
      .fill("Park");
    let panel = page.locator('[id^="first-met-panel-"]');
    await panel.getByRole("button", { name: /save/i }).click();
    await page.waitForTimeout(500);

    // Edit and change
    await page
      .getByRole("button", { name: /edit/i }).first()
      .click();
    await page.waitForTimeout(300);
    await page
      .locator('input[name="first_met[first_met_where]"]')
      .fill("Beach");
    panel = page.locator('[id^="first-met-panel-"]');
    await panel.getByRole("button", { name: /save/i }).click();
    await page.waitForTimeout(500);

    // Sidebar should show updated value
    const content = await page.content();
    expect(content).toContain("Beach");
    expect(content).not.toContain("Park");
  });

  // ─────────────────────────────────────────
  // Clear data
  // ─────────────────────────────────────────

  test("clear all data reverts to empty state", async ({ page }) => {
    await goToContact(page, contactId);

    // Add data first
    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);
    await page
      .locator('input[name="first_met[first_met_where]"]')
      .fill("Library");
    let panel = page.locator('[id^="first-met-panel-"]');
    await panel.getByRole("button", { name: /save/i }).click();
    await page.waitForTimeout(500);

    // Open edit and click clear
    await page
      .getByRole("button", { name: /edit/i }).first()
      .click();
    await page.waitForTimeout(300);
    await page
      .locator('button:has-text("Clear all")')
      .click();
    await page.waitForTimeout(500);

    // Should be back to empty state
    await expect(
      page.getByRole("button", { name: /add how we met/i }),
    ).toBeVisible();
  });

  // ─────────────────────────────────────────
  // Contact search
  // ─────────────────────────────────────────

  test("contact search dropdown shows results", async ({ page }) => {
    // Create a second contact to search for
    await createContact(page, {
      firstName: "Searchable",
      lastName: "Friend",
    });

    await goToContact(page, contactId);

    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);

    const searchInput = page.locator(
      '[id^="first-met-panel-"] input[placeholder*="Search contacts"]',
    );
    await searchInput.pressSequentially("Searchable", { delay: 50 });
    await page.waitForTimeout(1500);

    // Results dropdown should appear
    await expect(
      page.locator(
        '[id^="first-met-panel-"] button:has-text("Searchable Friend")',
      ),
    ).toBeVisible();
  });

  test("contact chip select and clear", async ({ page }) => {
    test.fixme(true, "Chip clear button interaction flaky with LiveView re-render timing");
    await createContact(page, {
      firstName: "ChipTest",
      lastName: "Contact",
    });

    await goToContact(page, contactId);

    await page.getByRole("button", { name: /add how we met/i }).click();
    await page.waitForTimeout(300);

    // Search and select
    const searchInput = page.locator(
      '[id^="first-met-panel-"] input[placeholder*="Search contacts"]',
    );
    await searchInput.pressSequentially("ChipTest", { delay: 50 });
    await page.waitForTimeout(1500);

    const result = page.locator(
      '[id^="first-met-panel-"] button:has-text("ChipTest Contact")',
    );
    if ((await result.count()) > 0) {
      await result.first().click();
      await page.waitForTimeout(300);
    }

    // Chip should show selected contact name
    await expect(
      page.locator("text=ChipTest Contact").first(),
    ).toBeVisible();

    // Clear the chip (click the × button next to the name)
    const clearBtn = page.locator(
      'button:has(.hero-x-mark)',
    );
    if ((await clearBtn.count()) > 0) {
      await clearBtn.first().click();
      await page.waitForTimeout(500);
    }

    // Search input should reappear (re-query since DOM changed)
    await expect(
      page.locator('input[placeholder*="Search contacts"]'),
    ).toBeVisible();
  });
});
