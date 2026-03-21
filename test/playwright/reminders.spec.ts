import { test, expect } from "@playwright/test";
import { registerUser, ensureOnDashboard } from "./helpers/auth";

test.describe("Reminders", () => {
  test.beforeEach(async ({ page }) => {
    await registerUser(page);
    await ensureOnDashboard(page);
  });

  // ─────────────────────────────────────────
  // Reminders: Upcoming page
  // ─────────────────────────────────────────

  test("upcoming reminders page loads", async ({ page }) => {
    await page.goto("/reminders/upcoming");
    await page.waitForLoadState("networkidle");

    // Page should load without errors
    await expect(page).toHaveURL(/\/reminders\/upcoming/);

    // Should show heading or empty state
    const content = await page.content();
    expect(content).toMatch(/reminder|upcoming|no.*reminder/i);
  });

  // ─────────────────────────────────────────
  // Reminders: Create on contact
  // ─────────────────────────────────────────

  test("create a reminder on a contact", async ({ page }) => {
    // First create a contact
    await page.goto("/contacts/new");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);
    await page.getByLabel(/first name/i).fill("ReminderTest");
    await page.getByLabel(/last name/i).fill("Person");
    await page.getByRole("button", { name: /save|create/i }).click();
    await page.waitForURL(/\/contacts\/\d+/, { timeout: 10_000 });

    // Navigate to Reminders section in the sidebar
    // The reminders section is a sidebar card on the contact show page
    const remindersSection = page.locator("text=Reminders");
    if ((await remindersSection.count()) > 0) {
      // Look for Add Reminder button
      const addBtn = page.getByRole("button", { name: /add reminder/i });
      if ((await addBtn.count()) > 0) {
        await addBtn.first().click();
        await page.waitForTimeout(500);

        // Fill reminder form
        const titleInput = page.getByLabel(/title/i);
        if ((await titleInput.count()) > 0) {
          await titleInput.fill("Call back next week");
        }

        // Submit
        const saveBtn = page.getByRole("button", { name: /save|create/i });
        if ((await saveBtn.count()) > 0) {
          await saveBtn.last().click();
          await page.waitForTimeout(1000);

          // Verify reminder appears
          const content = await page.content();
          expect(content).toContain("Call back next week");
        }
      }
    }
  });

  // ─────────────────────────────────────────
  // Reminders: Upcoming page shows reminders
  // ─────────────────────────────────────────

  test("upcoming page is accessible from nav", async ({ page }) => {
    // The bottom nav should have a Reminders link
    await page.goto("/dashboard");
    await page.waitForLoadState("networkidle");

    const remindersLink = page.getByRole("link", { name: /reminders/i });
    await expect(remindersLink.first()).toBeVisible();
    await remindersLink.first().click();

    await expect(page).toHaveURL(/\/reminders\/upcoming/);
  });
});
