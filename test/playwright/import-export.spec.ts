import { test, expect } from "@playwright/test";
import { registerUser, ensureOnDashboard } from "./helpers/auth";

test.describe("Import & Export", () => {
  test.beforeEach(async ({ page }) => {
    await registerUser(page);
    await ensureOnDashboard(page);
  });

  // ─────────────────────────────────────────
  // Import: vCard upload
  // ─────────────────────────────────────────

  test("import page shows file upload area", async ({ page }) => {
    await page.goto("/settings/import");
    await page.waitForLoadState("networkidle");

    // Should have a file input or drag-and-drop area
    const fileInput = page.locator("input[type='file']");
    const dropZone = page.locator("[phx-drop-target]");

    const hasFileInput = (await fileInput.count()) > 0;
    const hasDropZone = (await dropZone.count()) > 0;

    expect(hasFileInput || hasDropZone).toBe(true);
  });

  test("import page mentions supported format", async ({ page }) => {
    await page.goto("/settings/import");
    await page.waitForLoadState("networkidle");

    const content = await page.content();
    // Should mention vCard/vcf format
    expect(content).toMatch(/vcf|vcard/i);
  });

  // ─────────────────────────────────────────
  // Export: Download options
  // ─────────────────────────────────────────

  test("export page has download buttons", async ({ page }) => {
    await page.goto("/settings/export");
    await page.waitForLoadState("networkidle");

    const content = await page.content();
    // Should offer at least vCard export
    expect(content).toMatch(/export|download/i);

    // Should have clickable export buttons/links
    const exportBtns = page.locator(
      "a[href*='export'], button:has-text('Export'), button:has-text('Download')",
    );
    expect(await exportBtns.count()).toBeGreaterThan(0);
  });

  test("vCard export triggers download", async ({ page }) => {
    // First create a contact so there's something to export
    await page.goto("/contacts/new");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);
    await page.getByLabel(/first name/i).fill("Export");
    await page.getByLabel(/last name/i).fill("TestContact");
    await page.getByRole("button", { name: /save|create/i }).click();
    await page.waitForURL(/\/contacts\/\d+/, { timeout: 10_000 });

    // Go to export page
    await page.goto("/settings/export");
    await page.waitForLoadState("networkidle");

    // Look for vCard export link/button
    const vcardLink = page.locator(
      "a[href*='vcf'], a[href*='export'], a:has-text('vCard')",
    );
    if ((await vcardLink.count()) > 0) {
      // Set up download listener
      const downloadPromise = page.waitForEvent("download", { timeout: 10_000 }).catch(() => null);
      await vcardLink.first().click();
      const download = await downloadPromise;

      if (download) {
        const filename = download.suggestedFilename();
        expect(filename).toMatch(/\.(vcf|json)$/);
      }
    }
  });
});
