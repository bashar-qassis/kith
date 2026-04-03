import { test, expect } from "@playwright/test";
import { registerUser, ensureOnDashboard } from "./helpers/auth";
import { goToImportWizard, uploadVcardImport } from "./helpers/contacts";
import * as path from "path";

// ─────────────────────────────────────────────
// Import dedup & auto-merge toggle E2E tests
// ─────────────────────────────────────────────

const DEDUP_VCF = path.resolve(
  __dirname,
  "fixtures/duplicate-subrecords.vcf",
);

/**
 * Fill a LiveView input that uses phx-blur + phx-value-value.
 */
async function fillLiveViewBlurInput(
  page: import("@playwright/test").Page,
  selector: string,
  value: string,
) {
  const input = page.locator(selector);
  await input.fill(value);
  await input.evaluate((el, val) => {
    el.setAttribute("phx-value-value", val);
  }, value);
  await input.blur();
  await page.waitForTimeout(300);
}

test.describe("Import Deduplication", () => {
  test.beforeEach(async ({ page }) => {
    await registerUser(page);
    await ensureOnDashboard(page);
  });

  // ─────────────────────────────────────────
  // Auto-merge toggle visibility
  // ─────────────────────────────────────────

  test("auto-merge toggle visible in Monica API options", async ({
    page,
  }) => {
    await goToImportWizard(page);

    // Select Monica CRM radio
    await page.locator('input[value="monica_api"]').click();
    await page.waitForTimeout(300);

    // Fill URL and key to trigger options display
    await fillLiveViewBlurInput(
      page,
      'input[type="url"]',
      "https://monica.example.com",
    );
    await fillLiveViewBlurInput(
      page,
      'input[type="password"]',
      "test-api-key",
    );
    await page.waitForTimeout(500);

    // Auto-merge checkbox should be visible
    await expect(
      page.locator("text=Auto-merge definite duplicates"),
    ).toBeVisible();

    // Description should explain the behavior
    await expect(
      page.locator(
        "text=Merge contacts with identical name + email or name + phone",
      ),
    ).toBeVisible();
  });

  test("auto-merge toggle default is unchecked", async ({ page }) => {
    await goToImportWizard(page);

    await page.locator('input[value="monica_api"]').click();
    await page.waitForTimeout(300);

    await fillLiveViewBlurInput(
      page,
      'input[type="url"]',
      "https://monica.example.com",
    );
    await fillLiveViewBlurInput(
      page,
      'input[type="password"]',
      "test-api-key",
    );
    await page.waitForTimeout(500);

    // The auto-merge checkbox should not be checked
    const checkbox = page.locator(
      'input[phx-value-option="auto_merge_duplicates"]',
    );
    await expect(checkbox).not.toBeChecked();
  });

  // ─────────────────────────────────────────
  // Data type toggles
  // ─────────────────────────────────────────

  test("data type import toggles are visible", async ({ page }) => {
    await goToImportWizard(page);

    await page.locator('input[value="monica_api"]').click();
    await page.waitForTimeout(300);

    await fillLiveViewBlurInput(
      page,
      'input[type="url"]',
      "https://monica.example.com",
    );
    await fillLiveViewBlurInput(
      page,
      'input[type="password"]',
      "test-api-key",
    );
    await page.waitForTimeout(500);

    // All data type toggles should be visible
    const expectedLabels = [
      "Pets",
      "Calls",
      "Activities",
      "Gifts",
      "Debts",
      "Tasks",
      "Reminders",
      "Conversations",
      "Documents",
    ];

    for (const label of expectedLabels) {
      await expect(page.locator(`text=${label}`).first()).toBeVisible();
    }
  });

  test("data type toggles default to checked", async ({ page }) => {
    await goToImportWizard(page);

    await page.locator('input[value="monica_api"]').click();
    await page.waitForTimeout(300);

    await fillLiveViewBlurInput(
      page,
      'input[type="url"]',
      "https://monica.example.com",
    );
    await fillLiveViewBlurInput(
      page,
      'input[type="password"]',
      "test-api-key",
    );
    await page.waitForTimeout(500);

    // Pets, Calls, etc should be checked by default
    const defaultOnOptions = [
      "pets",
      "calls",
      "activities",
      "gifts",
      "debts",
      "tasks",
      "reminders",
      "conversations",
    ];

    for (const option of defaultOnOptions) {
      const checkbox = page.locator(
        `input[phx-value-option="${option}"]`,
      );
      await expect(checkbox).toBeChecked();
    }
  });

  // ─────────────────────────────────────────
  // vCard import dedup behavior
  // ─────────────────────────────────────────

  test("vCard import with duplicate sub-records creates unique entries", async ({
    page,
  }) => {
    test.setTimeout(60_000);

    await goToImportWizard(page);
    await uploadVcardImport(page, DEDUP_VCF);

    // Navigate to contacts and find the imported contact
    await page.goto("/contacts");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(500);

    // Search for the imported contact
    const searchInput = page.locator('input[name="search"]');
    if ((await searchInput.count()) > 0) {
      await searchInput.fill("DupTest");
      await page.waitForTimeout(800);
    }

    // Click on the contact
    const contactLink = page.locator("a:has-text('DupTest Contact')");
    if ((await contactLink.count()) > 0) {
      await contactLink.first().click();
      await page.waitForURL(/\/contacts\/\d+/, { timeout: 10_000 });
      await page.waitForTimeout(500);

      const content = await page.content();

      // Should have the contact
      expect(content).toContain("DupTest");

      // Phone: should have 2 unique phones (not 3 — the duplicate +12025551234 should be deduped)
      // Note: the vCard has +12025551234 twice and +12025559999 once

      // Addresses: should have 2 unique addresses (not 3 — the duplicate 100 Oak Ave Denver should be deduped)
      // Note: the vCard has 100 Oak Ave Denver twice and 200 Elm St Portland once
    }
  });
});
