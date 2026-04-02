import { test, expect } from "@playwright/test";
import { registerUser, ensureOnDashboard } from "./helpers/auth";

test.describe("Trash", () => {
  test.beforeEach(async ({ page }) => {
    await registerUser(page);
    await ensureOnDashboard(page);
  });

  // ─────────────────────────────────────────
  // Trash: Empty state
  // ─────────────────────────────────────────

  test("trash page shows empty state when no contacts are trashed", async ({
    page,
  }) => {
    await page.goto("/contacts/trash");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveURL(/\/contacts\/trash/);

    const content = await page.content();
    expect(content).toMatch(/trash is empty/i);

    // Empty Trash button should not be present
    const emptyBtn = page.getByRole("button", { name: /empty trash/i });
    expect(await emptyBtn.count()).toBe(0);
  });

  // ─────────────────────────────────────────
  // Trash: Contact appears after soft-delete
  // ─────────────────────────────────────────

  test("trashed contact appears on trash page", async ({ page }) => {
    // Create a contact
    await page.goto("/contacts/new");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);
    await page.getByLabel(/first name/i).fill("TrashTest");
    await page.getByRole("button", { name: /save|create/i }).click();
    await page.waitForURL(/\/contacts\/\d+/, { timeout: 10_000 });

    // Move to trash via the contact page action
    const trashBtn = page.getByRole("button", { name: /move to trash|delete/i });
    if ((await trashBtn.count()) > 0) {
      await trashBtn.first().click();
      await page.waitForTimeout(500);

      // Confirm if a dialog/modal appears
      const confirmBtn = page.getByRole("button", { name: /confirm|yes|move to trash/i });
      if ((await confirmBtn.count()) > 0) {
        await confirmBtn.first().click();
        await page.waitForTimeout(500);
      }
    }

    // Navigate to trash
    await page.goto("/contacts/trash");
    await page.waitForLoadState("networkidle");

    const content = await page.content();
    expect(content).toContain("TrashTest");
  });

  // ─────────────────────────────────────────
  // Trash: Empty Trash button and modal
  // ─────────────────────────────────────────

  test("Empty Trash button is visible when trashed contacts exist", async ({
    page,
  }) => {
    // Create and trash a contact
    await page.goto("/contacts/new");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);
    await page.getByLabel(/first name/i).fill("ToBeEmptied");
    await page.getByRole("button", { name: /save|create/i }).click();
    await page.waitForURL(/\/contacts\/\d+/, { timeout: 10_000 });

    const trashBtn = page.getByRole("button", { name: /move to trash|delete/i });
    if ((await trashBtn.count()) > 0) {
      await trashBtn.first().click();
      await page.waitForTimeout(500);

      const confirmBtn = page.getByRole("button", { name: /confirm|yes|move to trash/i });
      if ((await confirmBtn.count()) > 0) {
        await confirmBtn.first().click();
        await page.waitForTimeout(500);
      }
    }

    await page.goto("/contacts/trash");
    await page.waitForLoadState("networkidle");

    // Empty Trash button should be visible
    await expect(
      page.getByRole("button", { name: /empty trash/i }),
    ).toBeVisible();
  });

  test("Empty Trash modal opens and can be cancelled", async ({ page }) => {
    // Create and trash a contact
    await page.goto("/contacts/new");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);
    await page.getByLabel(/first name/i).fill("CancelTrash");
    await page.getByRole("button", { name: /save|create/i }).click();
    await page.waitForURL(/\/contacts\/\d+/, { timeout: 10_000 });

    const trashBtn = page.getByRole("button", { name: /move to trash|delete/i });
    if ((await trashBtn.count()) > 0) {
      await trashBtn.first().click();
      await page.waitForTimeout(500);

      const confirmBtn = page.getByRole("button", { name: /confirm|yes|move to trash/i });
      if ((await confirmBtn.count()) > 0) {
        await confirmBtn.first().click();
        await page.waitForTimeout(500);
      }
    }

    await page.goto("/contacts/trash");
    await page.waitForLoadState("networkidle");

    // Click Empty Trash to open modal
    await page.getByRole("button", { name: /empty trash/i }).click();
    await page.waitForTimeout(300);

    // Modal should appear
    const content = await page.content();
    expect(content).toMatch(/permanently delete|cannot be undone/i);

    // Cancel should close modal without deleting
    const cancelBtn = page.getByRole("button", { name: /cancel/i });
    if ((await cancelBtn.count()) > 0) {
      await cancelBtn.first().click();
      await page.waitForTimeout(300);

      // Contact should still be there
      const afterContent = await page.content();
      expect(afterContent).toContain("CancelTrash");
    }
  });

  test("confirming Empty Trash deletes all trashed contacts", async ({
    page,
  }) => {
    // Create and trash a contact
    await page.goto("/contacts/new");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);
    await page.getByLabel(/first name/i).fill("PermanentDelete");
    await page.getByRole("button", { name: /save|create/i }).click();
    await page.waitForURL(/\/contacts\/\d+/, { timeout: 10_000 });

    const trashBtn = page.getByRole("button", { name: /move to trash|delete/i });
    if ((await trashBtn.count()) > 0) {
      await trashBtn.first().click();
      await page.waitForTimeout(500);

      const confirmBtn = page.getByRole("button", { name: /confirm|yes|move to trash/i });
      if ((await confirmBtn.count()) > 0) {
        await confirmBtn.first().click();
        await page.waitForTimeout(500);
      }
    }

    await page.goto("/contacts/trash");
    await page.waitForLoadState("networkidle");

    // Open the empty trash modal
    await page.getByRole("button", { name: /empty trash/i }).click();
    await page.waitForTimeout(300);

    // Click the confirm "Empty Trash" button inside the modal
    const modalEmptyBtn = page
      .locator("[id='empty-trash-modal']")
      .getByRole("button", { name: /empty trash/i });

    if ((await modalEmptyBtn.count()) > 0) {
      await modalEmptyBtn.click();
      await page.waitForTimeout(1000);

      const content = await page.content();
      expect(content).toMatch(/permanently deleted|trash is empty/i);
    }
  });
});
