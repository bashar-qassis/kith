# Phase 06: Reminders & Notifications

> **Status:** Implemented
> **Depends on:** Phase 03 (Core Domain Models), Phase 04 (Contact Management)
> **Blocks:** Phase 07 (Integrations — Oban patterns), Phase 10 (REST API — reminder endpoints), Phase 11 (Frontend — Upcoming Reminders page)

## Overview

This phase implements the full reminder lifecycle: CRUD operations, automatic birthday reminders, stay-in-touch semantics, one-time and recurring reminders, pre-notification scheduling, and the Oban workers that drive nightly scheduling and notification delivery. It also includes the ContactPurgeWorker for 30-day trash cleanup and the Upcoming Reminders LiveView page.

---

## Decisions

- **Decision A:** ReminderInstance uses `fired_at` (not `triggered_at`) for the timestamp when the notification was sent. All schema references, queries, and tests must use `fired_at`.
- **Decision B:** Alter migration approach — Phase 03 created initial scaffolding tables; Phase 06 adds an alter migration (`20260319110524`) to restructure columns and indexes rather than modifying the original migration. This preserves migration history.
- **Decision C:** `reminder_rules` restructured from per-reminder to per-account — the original Phase 03 migration had rules as children of reminders, but Phase 06 plan specifies account-level pre-notification config. The alter migration drops and recreates the table.
- **Decision D:** Uses Elixir stdlib `DateTime.from_naive!/2` + `DateTime.shift_zone!/2` with `Tz` database instead of Timex for timezone conversions. Timex is in deps but `Tz` was already configured as `:time_zone_database`.
- **Decision E:** `Scope` uses `account_id` integer scoping (not a `%Scope{}` struct) — the plan references `%Scope{}` but the existing codebase pattern uses `import Kith.Scope` with `scope_to_account(queryable, account_id)`. All Phase 06 functions follow the existing pattern.
- **Decision F:** Oban cron schedule uses 2 AM UTC for ReminderSchedulerWorker and 3 AM UTC for ContactPurgeWorker (plan said 0 AM and 1 AM respectively, but config already had 2 AM and 3 AM from Phase 03 scaffolding).

---

## Tasks

### TASK-06-01: Reminder and ReminderInstance Ecto Schemas
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-xx (core schema migrations)
**Description:**
Create the `reminders` and `reminder_instances` database tables and Ecto schemas.

**`reminders` table:**
- `id` (bigint PK)
- `account_id` (FK → accounts, NOT NULL)
- `contact_id` (FK → contacts, NOT NULL, ON DELETE CASCADE)
- `creator_id` (FK → users, NOT NULL)
- `type` (string, NOT NULL — one of: `birthday`, `stay_in_touch`, `one_time`, `recurring`)
- `title` (string, nullable — auto-generated for birthday/stay-in-touch, user-defined for one-time/recurring)
- `frequency` (string, nullable — `weekly`, `biweekly`, `monthly`, `3months`, `6months`, `annually`; required for `stay_in_touch` and `recurring`)
- `next_reminder_date` (date, NOT NULL)
- `enqueued_oban_job_ids` (jsonb, DEFAULT '[]')
- `active` (boolean, DEFAULT true)
- `inserted_at`, `updated_at` (timestamps)

**`reminder_instances` table:**
- `id` (bigint PK)
- `account_id` (FK → accounts, NOT NULL)
- `reminder_id` (FK → reminders, NOT NULL, ON DELETE CASCADE)
- `contact_id` (FK → contacts, NOT NULL, ON DELETE CASCADE)
- `status` (string, NOT NULL — one of: `pending`, `resolved`, `dismissed`, `failed`)
- `scheduled_for` (utc_datetime, NOT NULL)
- `fired_at` (utc_datetime, nullable — when notification was sent)
- `resolved_at` (utc_datetime, nullable)
- `inserted_at`, `updated_at` (timestamps)

**Indexes:**
- `CREATE INDEX reminders_contact_idx ON reminders (contact_id) WHERE active = true`
- `CREATE INDEX reminders_account_next_date_idx ON reminders (account_id, next_reminder_date) WHERE active = true`
- `CREATE UNIQUE INDEX reminders_birthday_unique_idx ON reminders (contact_id) WHERE type = 'birthday'` — one birthday reminder per contact
- `CREATE INDEX reminder_instances_pending_idx ON reminder_instances (reminder_id) WHERE status = 'pending'`

**Acceptance Criteria:**
- [ ] Migration creates both tables with all columns, FKs, and indexes
- [ ] Ecto schemas with changesets and type validations
- [ ] `frequency` is required when `type` is `stay_in_touch` or `recurring`
- [ ] `frequency` is nil/ignored for `one_time` reminders; changeset rejects non-nil frequency on one-time
- [ ] Changeset validates `frequency` against allowed enum (`weekly`, `biweekly`, `monthly`, `3months`, `6months`, `annually`) and rejects unknown values
- [ ] `status` on `reminder_instances` allows: `pending`, `resolved`, `dismissed`, `failed`
- [ ] `:failed` status: Set by `ReminderNotificationWorker` when the Swoosh email delivery raises an exception that exhausts all Oban retries. The final Oban `handle_failure/2` callback (or equivalent) sets the ReminderInstance status to `:failed`. A failed instance does NOT block future stay-in-touch re-enqueueing — the next scheduled reminder for that contact will still be created normally.
- [ ] Birthday uniqueness enforced at DB level (partial unique index)
- [ ] `enqueued_oban_job_ids` defaults to empty JSON array

**Safeguards:**
> ⚠️ Do NOT use Postgres enums for `type`, `status`, or `frequency` — use string columns with Ecto-level validation. This avoids migration pain when adding new types later.

**Notes:**
- The `type` field uses strings validated in the Ecto changeset, consistent with the seeded-table pattern used elsewhere in the app.
- `enqueued_oban_job_ids` is a jsonb array of integers (Oban job IDs).

---

### TASK-06-02: ReminderRule Schema (Account-Level Pre-Notification Config)
**Priority:** High
**Effort:** S
**Depends on:** TASK-06-01
**Description:**
Create the `reminder_rules` table and schema. ReminderRules are account-level settings that control pre-notification behavior.

**`reminder_rules` table:**
- `id` (bigint PK)
- `account_id` (FK → accounts, NOT NULL)
- `days_before` (integer, NOT NULL — e.g., 30, 7, 0)
- `active` (boolean, DEFAULT true)
- `inserted_at`, `updated_at` (timestamps)

Seed default rules per account on account creation: `{days_before: 30, active: true}`, `{days_before: 7, active: true}`, `{days_before: 0, active: true}`.

**Acceptance Criteria:**
- [ ] Migration creates table
- [ ] Account creation seeds three default ReminderRules
- [ ] Admin can toggle `active` on each rule via settings
- [ ] Unique index on `(account_id, days_before)`

**Safeguards:**
> ⚠️ The `days_before: 0` rule (on-day notification) should not be deletable — only toggleable. Enforce this in the context, not the schema.

**Notes:**
- Pre-notifications only apply to `birthday` and `one_time` reminder types. Stay-in-touch and recurring reminders fire on-day only.

---

### TASK-06-03: Reminder CRUD Context (`Kith.Reminders`)
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-06-01, TASK-06-02
**Description:**
Implement the `Kith.Reminders` context module with full CRUD operations. All mutations must use `Ecto.Multi` to transactionally manage both the reminder record and its associated Oban jobs.

**Functions:**

`create_reminder/2` (`%Scope{}`, attrs):
1. Insert the reminder record
2. Compute scheduled Oban jobs based on `next_reminder_date`, account `send_hour`/`timezone`, and active ReminderRules
3. Enqueue Oban jobs (up to 3: 30-day pre, 7-day pre, on-day)
4. Store job IDs in `enqueued_oban_job_ids`
5. All within a single `Ecto.Multi`

`update_reminder/2` (reminder, attrs):
1. Cancel all existing Oban jobs listed in `enqueued_oban_job_ids`
2. Update the reminder record
3. Recompute and enqueue new Oban jobs
4. Store new job IDs in `enqueued_oban_job_ids`
5. All within a single `Ecto.Multi`

`delete_reminder/1` (reminder):
1. Cancel all enqueued Oban jobs
2. Delete the reminder record
3. All within a single `Ecto.Multi`

`list_reminders/2` (`%Scope{}`, contact_id) — list active reminders for a contact.

`get_reminder!/2` (`%Scope{}`, id) — fetch by ID with scope enforcement.

**Acceptance Criteria:**
- [ ] `create_reminder/2` inserts reminder + enqueues Oban jobs in one transaction
- [ ] `update_reminder/2` cancels old jobs + updates + enqueues new jobs in one transaction
- [ ] `delete_reminder/1` cancels jobs + deletes in one transaction
- [ ] All functions enforce `account_id` scoping via `%Scope{}`
- [ ] Oban job IDs are correctly stored in `enqueued_oban_job_ids` after each mutation

**Safeguards:**
> ⚠️ `Oban.cancel_job/1` is NOT transactional with Ecto — it issues a separate DB update. If the Ecto.Multi rolls back, the Oban job cancellation is NOT rolled back. This is acceptable: a cancelled-but-orphaned job is harmless (it will be a no-op when it fires). The reverse (committed reminder change but un-cancelled job) would be worse, so cancel FIRST in the Multi step ordering.

> ⚠️ Never call `Oban.insert` outside of `Ecto.Multi`. Use `Oban.insert/3` with the multi's repo to ensure transactional enqueue.

**Notes:**
- Use `Oban.insert_all/3` within Multi for batch job insertion (30-day, 7-day, on-day).
- The standard cancellation pattern (see TASK-06-10) must be followed in all three mutation functions.

---

### TASK-06-04: Birthday Reminder Auto-Creation
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-06-03
**Description:**
When a contact's birthdate is set or changed, automatically manage the associated birthday reminder. This logic integrates with the Contact update flow.

**Scenarios:**

1. **Birthdate set (create or edit, was NULL):** Call `Kith.Reminders.create_birthday_reminder/1` within the contact's `Ecto.Multi`. This creates a `type: birthday` reminder with `next_reminder_date` computed as the next occurrence of the birthday (this year if not yet passed, next year if already passed). Enqueue Oban jobs per active ReminderRules.

2. **Birthdate changed:** Cancel old birthday reminder's Oban jobs and delete the old reminder. Create a new birthday reminder with the updated date. All within the contact update `Ecto.Multi`.

3. **Birthdate removed (set to NULL):** Cancel the birthday reminder's Oban jobs and delete the birthday reminder. Within the contact update `Ecto.Multi`.

**February 29 handling:**
When computing `next_reminder_date` for a Feb 29 birthday:
- If the target year is a leap year → Feb 29
- If the target year is NOT a leap year → Feb 28

```elixir
# Example implementation sketch
defp next_birthday_date(%Date{month: 2, day: 29}, target_year) do
  if Date.leap_year?(%Date{year: target_year, month: 1, day: 1}) do
    Date.new!(target_year, 2, 29)
  else
    Date.new!(target_year, 2, 28)
  end
end
```

**Acceptance Criteria:**
- [ ] Setting birthdate on a contact auto-creates a birthday reminder
- [ ] Changing birthdate cancels old reminder and creates new one
- [ ] Removing birthdate cancels and deletes birthday reminder
- [ ] Feb 29 birthdays fire on Feb 28 in non-leap years
- [ ] All operations are within the contact update `Ecto.Multi`
- [ ] Only one birthday reminder per contact (enforced by partial unique index)

**Safeguards:**
> ⚠️ The birthday auto-creation must be called from the Contacts context (Phase 04), not from a separate hook or callback. This ensures transactional integrity. Phase 04 must include the `Kith.Reminders.create_birthday_reminder/1` call in its contact create/update Multi.

**Notes:**
- `create_birthday_reminder/1` takes a contact struct (with `birthdate` populated) and returns `{:ok, reminder}` or `{:error, changeset}`.
- Title is auto-generated: "{contact.display_name}'s birthday".

---

### TASK-06-05: Stay-in-Touch Reminder Semantics
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-06-03
**Description:**
Implement the stay-in-touch reminder type with its unique re-fire and resolution semantics.

**Frequency options:** `weekly` (7d), `biweekly` (14d), `monthly` (30d), `3months` (90d), `6months` (180d), `annually` (365d).

**Core rules:**

1. **No re-enqueue while pending:** The ReminderSchedulerWorker checks for a `ReminderInstance` with `status: :pending` for this reminder. If one exists, skip enqueuing. This prevents notification spam.

2. **Resolution via Activity/Call:** When an Activity or Call is logged for a contact, call `Kith.Reminders.resolve_stay_in_touch_instance/1` within the same `Ecto.Multi`. This function:
   - Finds the contact's stay-in-touch reminder (if any)
   - Finds the pending ReminderInstance for that reminder (if any)
   - Sets `status: :resolved`, `resolved_at: DateTime.utc_now()`
   - Updates `reminder.next_reminder_date` to `Date.utc_today() + frequency_days`
   - Clears `enqueued_oban_job_ids` (jobs already fired or will be no-ops)

3. **Archiving contact:** Within the archive `Ecto.Multi`:
   - Cancel all stay-in-touch Oban jobs
   - Mark any pending ReminderInstances as `:dismissed`
   - Set `reminder.active = false`

4. **Unarchiving contact:** Does NOT auto-re-enable stay-in-touch. User must manually update the stay-in-touch frequency to re-enable. This is intentional — avoid surprising the user.

5. **Re-fire after resolution:** The nightly ReminderSchedulerWorker sees `next_reminder_date` has passed and no pending instance exists → enqueues a new job.

**Acceptance Criteria:**
- [ ] Stay-in-touch reminder does not re-enqueue while a pending ReminderInstance exists
- [ ] Logging Activity for a contact resolves its pending stay-in-touch instance
- [ ] Logging Call for a contact resolves its pending stay-in-touch instance
- [ ] After resolution, `next_reminder_date` is updated to now + interval
- [ ] Archiving cancels stay-in-touch jobs and dismisses pending instances
- [ ] Unarchiving does NOT re-enable stay-in-touch

**Safeguards:**
> ⚠️ The `resolve_stay_in_touch_instance/1` function is called from the Interactions context (Activities/Calls). This is a cross-context call that must be included in the Activity/Call creation `Ecto.Multi`. Coordinate with Phase 05 (contact-architect).

**Notes:**
- `resolve_stay_in_touch_instance/1` accepts a `contact_id` and returns `{:ok, :resolved}` or `{:ok, :no_pending_instance}`. It is safe to call even if no stay-in-touch reminder exists for the contact.

---

### TASK-06-06: One-Time Reminder
**Priority:** High
**Effort:** S
**Depends on:** TASK-06-03
**Description:**
Implement one-time reminder behavior. A one-time reminder fires exactly once on `next_reminder_date` and does not re-enqueue.

**Behavior:**
- User creates a one-time reminder with a `title` and `next_reminder_date`.
- Oban jobs are enqueued based on active ReminderRules (30-day pre, 7-day pre, on-day).
- When the on-day job fires, a `ReminderInstance` is created with `status: :pending`.
- No further scheduling occurs. The reminder remains in the DB for history.
- Pre-notifications (30-day, 7-day) also create ReminderInstances but these are informational — they do not block the on-day notification.

**Frequency validation:**
For `one_time` reminders, the `frequency` field is ignored and should be set to `nil`. The changeset must explicitly allow `nil` for `frequency` when `type == :one_time`. A changeset validation must reject any non-nil `frequency` value for one-time reminders to prevent confusion.

**Acceptance Criteria:**
- [ ] One-time reminder fires exactly once
- [ ] Pre-notifications fire at configured intervals
- [ ] No re-enqueue after on-day fire
- [ ] Reminder record persists after firing (for history)
- [ ] `frequency` field is ignored (nil) for one-time reminders; changeset rejects non-nil values

**Notes:**
- After firing, `enqueued_oban_job_ids` is cleared and `active` can optionally be set to `false`.

---

### TASK-06-07: Recurring Reminder
**Priority:** High
**Effort:** M
**Depends on:** TASK-06-03
**Description:**
Implement recurring reminder behavior. A recurring reminder fires on `next_reminder_date`, then re-enqueues for the next interval.

**Behavior:**
- User creates a recurring reminder with `title`, `frequency`, and `next_reminder_date`.
- When the on-day job fires:
  1. Create a `ReminderInstance` with `status: :pending`
  2. Compute the next occurrence: `next_reminder_date + frequency_interval`
  3. Update `reminder.next_reminder_date` to the new date
  4. Clear `enqueued_oban_job_ids` (the nightly scheduler will re-enqueue for the next occurrence)
- Recurring reminders do NOT support pre-notifications (30-day, 7-day). They fire on-day only.

**Frequency validation:**
For `recurring` (and `daily`/`weekly`/`monthly`/`yearly` if used) reminders, `frequency` must be set and must match the allowed enum: `weekly`, `biweekly`, `monthly`, `3months`, `6months`, `annually`. Add a changeset validation (`validate_inclusion/4`) that rejects unknown frequency values. The changeset must also require `frequency` to be present when `type` is `recurring`.

**Acceptance Criteria:**
- [ ] Recurring reminder fires on `next_reminder_date`
- [ ] After firing, `next_reminder_date` advances by one interval
- [ ] Nightly scheduler picks up the new date and enqueues for next occurrence
- [ ] No pre-notifications for recurring reminders
- [ ] `frequency` is required for recurring reminders; changeset rejects absent or unknown values
- [ ] Changeset rejects any `frequency` value not in the allowed enum

**Notes:**
- `frequency` uses the same options as stay-in-touch: weekly, biweekly, monthly, 3months, 6months, annually.

---

### TASK-06-07b: Expose `cancel_all_for_contact/2` for Contact Merge
**Priority:** High
**Effort:** XS
**Depends on:** TASK-06-10
**Description:**
Expose a `cancel_all_for_contact/2` function in the `Reminders` context:

- **Signature:** `cancel_all_for_contact(contact_id, account_id)`
- **Purpose:** Cancels all active Oban jobs listed in `enqueued_oban_job_ids` for all reminders belonging to the contact.
- **Design:** Intended to be called as a step inside a caller-provided `Ecto.Multi` (e.g., from the contact merge flow in Phase 09).
- **Returns:** A list of `Oban.cancel_job/1` results.

> **Note:** Contact merge (Phase 09) is responsible for calling this function for the non-survivor contact inside its `Ecto.Multi`. Phase 06 must expose this function.

**Acceptance Criteria:**
- [ ] `Reminders.cancel_all_for_contact/2` exists
- [ ] Calling it cancels all Oban jobs in `enqueued_oban_job_ids` for all of the contact's reminders
- [ ] Function is documented with a note that it should be called within an `Ecto.Multi` step

---

### TASK-06-08: ReminderSchedulerWorker (Oban Cron)
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-06-03, TASK-06-05, TASK-06-06, TASK-06-07
**Description:**
Implement the nightly Oban cron worker that scans for due reminders and enqueues notification jobs.

**Schedule:** Runs at `00:00 UTC` daily via Oban cron configuration.

**Algorithm:**
```
for each account:
  load account.timezone, account.send_hour
  load active ReminderRules for account

  for each active reminder where next_reminder_date is within next 24 hours:
    # Skip if already enqueued
    if reminder.enqueued_oban_job_ids is not empty:
      continue

    # Skip stay-in-touch with pending instance
    if reminder.type == :stay_in_touch:
      if pending ReminderInstance exists for this reminder:
        continue

    # Compute UTC scheduled_at from account timezone + send_hour
    scheduled_at = Timex.to_datetime(
      NaiveDateTime.new!(reminder.next_reminder_date, Time.new!(send_hour, 0, 0)),
      account.timezone
    ) |> Timex.Timezone.convert("Etc/UTC")

    # Determine which jobs to enqueue
    jobs = []
    if reminder.type in [:birthday, :one_time]:
      for rule in active_rules where rule.days_before > 0:
        pre_date = Date.add(reminder.next_reminder_date, -rule.days_before)
        if pre_date >= Date.utc_today():
          pre_scheduled_at = compute_utc(pre_date, send_hour, timezone)
          jobs << %{type: :pre_notification, days_before: rule.days_before, scheduled_at: pre_scheduled_at}

    jobs << %{type: :on_day, scheduled_at: scheduled_at}

    # Enqueue all jobs in Ecto.Multi
    enqueue_jobs_in_multi(reminder, jobs)
```

**Acceptance Criteria:**
- [ ] Worker runs nightly at 00:00 UTC
- [ ] Correctly converts account timezone + send_hour to UTC scheduled_at
- [ ] Skips reminders that already have enqueued job IDs
- [ ] Skips stay-in-touch reminders with pending instances
- [ ] Enqueues pre-notification jobs for birthday and one-time types
- [ ] Stores all job IDs in `enqueued_oban_job_ids`
- [ ] Idempotent: running twice within 24h does not double-enqueue

**Safeguards:**
> ⚠️ Use `Timex.to_datetime/2` with IANA timezone names, never UTC offsets. This ensures DST is handled correctly at scheduling time.

> ⚠️ The worker must be resilient to individual account/reminder failures — catch errors per-reminder and continue processing. Log errors but do not crash the entire worker run.

**Notes:**
- Oban cron config: `{"0 0 * * *", Kith.Workers.ReminderSchedulerWorker}`
- Consider batching accounts to avoid loading all reminders into memory at once.
- The "within next 24 hours" window means: `reminder.next_reminder_date <= Date.utc_today() + 1`.

---

### TASK-06-09: ReminderNotificationWorker (Oban Worker)
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-06-08
**Description:**
Implement the Oban worker that processes a single reminder notification. This worker is enqueued by the ReminderSchedulerWorker with a specific `scheduled_at` time.

**Job args:** `%{"reminder_id" => id, "type" => "on_day" | "pre_notification", "days_before" => integer}`

**Behavior:**
1. Load reminder with preloaded contact and account
2. Guard: if reminder no longer active, contact archived/deleted, or reminder deleted → discard job (`{:discard, reason}`)
3. Create `ReminderInstance` with `status: :pending`, `scheduled_for: scheduled_at`, `fired_at: DateTime.utc_now()`
4. Build notification email via Swoosh (subject line varies by type: birthday, stay-in-touch, one-time, recurring)
5. Deliver email via `Kith.Mailer.deliver/1`
6. On success: return `:ok`
7. On email failure: return `{:error, reason}` — Oban retries automatically

**Retry config:** `max_attempts: 3`, backoff: exponential (Oban default).

**After max retries exhausted:** Oban moves job to `discarded` state. The `ReminderInstance` is updated to `status: :failed` — this signals to the user that delivery was unsuccessful. No further retries are attempted.

**Email failure audit logging:**
When a reminder email fails to deliver (Swoosh returns an error), log an audit event:
```
{action: 'reminder.email_failed', resource_type: 'ReminderInstance', resource_id: id, metadata: {error: reason}}
```
Do NOT retry indefinitely — after 3 Oban attempts, mark the ReminderInstance as `failed` and stop retrying. This is handled by Oban's `max_attempts: 3` config; the worker should update the ReminderInstance status in the `handle_exhausted/1` callback (or equivalent Oban lifecycle hook).

**Acceptance Criteria:**
- [ ] At the top of `perform/1`, fetch the associated contact. If `contact.deceased == true`, mark the ReminderInstance status as `:dismissed` (update `status` field) and return `:ok` without sending an email. This prevents sending birthday/anniversary reminders for deceased contacts.
- [ ] Creates ReminderInstance on fire
- [ ] Sends notification email via Swoosh
- [ ] Guards against stale/deleted reminders (discards gracefully)
- [ ] Retries up to 3 times on email failure
- [ ] After 3 failed attempts, ReminderInstance status is set to `failed`
- [ ] Each email delivery failure logs an audit event with `action: 'reminder.email_failed'` and error reason
- [ ] Pre-notification emails have distinct subject lines (e.g., "Reminder: {name}'s birthday in 7 days")

**Safeguards:**
> ⚠️ Always reload the reminder from DB at execution time — do not rely on stale data from enqueue time. The reminder may have been edited, deleted, or the contact archived between scheduling and firing.

**Notes:**
- Email templates are simple text/HTML. Subject lines:
  - Birthday on-day: "{name}'s birthday is today"
  - Birthday pre-30: "{name}'s birthday is in 30 days"
  - Birthday pre-7: "{name}'s birthday is in 7 days"
  - Stay-in-touch: "Time to reach out to {name}"
  - One-time on-day: "Reminder: {title}"
  - Recurring on-day: "Reminder: {title}"

---

### TASK-06-10: Oban Job Cancellation Pattern
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-06-03
**Description:**
Standardize and document the Oban job cancellation pattern used throughout the Reminders context. All reminder mutations must follow this pattern.

**Standard pattern:**
```elixir
defp cancel_enqueued_jobs_step(multi, reminder_key \\ :reminder) do
  Ecto.Multi.run(multi, :cancel_jobs, fn _repo, changes ->
    reminder = Map.get(changes, reminder_key)
    Enum.each(reminder.enqueued_oban_job_ids, fn job_id ->
      Oban.cancel_job(job_id)
    end)
    {:ok, :cancelled}
  end)
end
```

**Where this pattern is used:**
- `Kith.Reminders.update_reminder/2` — cancel before re-enqueue
- `Kith.Reminders.delete_reminder/1` — cancel before delete
- Birthday reminder recreation on birthdate change
- Contact archival (stay-in-touch cancellation)
- Contact soft-deletion (all reminder cancellation)
- Contact merge (non-survivor reminder cancellation)

**Acceptance Criteria:**
- [ ] Shared helper function in `Kith.Reminders` context
- [ ] All six call sites use this helper
- [ ] Pattern documented in module doc

**Safeguards:**
> ⚠️ `Oban.cancel_job/1` is idempotent — calling it on an already-cancelled or completed job is safe. Do not guard against this.

> ⚠️ Job cancellation is NOT rolled back if the Ecto.Multi transaction fails. This is the accepted tradeoff — a harmlessly cancelled job is better than an un-cancelled job firing on stale data.

**Notes:**
- `Oban.cancel_job/1` sets the job state to `cancelled` in the `oban_jobs` table. Cancelled jobs are not retried.

---

### TASK-06-11: ContactPurgeWorker (Oban Cron)
**Priority:** High
**Effort:** M
**Depends on:** TASK-06-01
**Description:**
Implement the nightly Oban cron worker that permanently hard-deletes contacts whose `deleted_at` timestamp is older than 30 days.

**Schedule:** Runs nightly (e.g., `01:00 UTC` to avoid overlap with ReminderSchedulerWorker).

**Algorithm:**
1. Query contacts where `deleted_at < NOW() - INTERVAL '30 days'`
2. Batch: process up to 500 contacts per run
3. For each contact:
   a. Cancel any enqueued Oban jobs for the contact's reminders
   b. Hard-delete the contact (CASCADE removes all sub-entities: notes, activities, calls, reminders, reminder_instances, addresses, contact_fields, relationships, life_events, documents, photos, tags associations)
   c. Create audit log entry: "Contact permanently purged after 30-day trash window." with `contact_id` (integer, no FK) and `contact_name` snapshot
4. Log total purged count

**Acceptance Criteria:**
- [ ] Only deletes contacts with `deleted_at` older than 30 days
- [ ] Batches at 500 to avoid long-running transactions
- [ ] CASCADE deletes all sub-entities
- [ ] Creates audit log entry per purged contact with name snapshot
- [ ] Cancels any remaining Oban jobs for the contact's reminders before deletion
- [ ] Idempotent: safe to run multiple times

**Safeguards:**
> ⚠️ Each contact deletion should be its own transaction — do not wrap all 500 in a single transaction. This prevents one bad record from blocking the entire batch.

> ⚠️ Audit log entries use plain integer `contact_id` (no FK) and a `contact_name` text snapshot. These entries intentionally survive the hard-delete.

**Notes:**
- Oban cron config: `{"0 1 * * *", Kith.Workers.ContactPurgeWorker}`
- If more than 500 contacts need purging, the next nightly run will catch the remainder.

---

### TASK-06-12: DST and Timezone Handling
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-06-08
**Description:**
Ensure all reminder scheduling correctly handles DST transitions and timezone conversions.

**Rules:**
1. Always store IANA timezone names (e.g., `"America/New_York"`) in the account record, never UTC offsets.
2. Use `Timex.to_datetime/2` to convert `{date, time}` tuples to timezone-aware datetimes.
3. Convert to UTC for Oban `scheduled_at` using `DateTime.shift_zone!/2` or `Timex.Timezone.convert/2`.
4. Never store or cache UTC offsets — always recompute from IANA name at scheduling time.

**DST verification:**
- A reminder for 14:00 America/New_York:
  - In winter (EST, UTC-5): scheduled_at = 19:00 UTC
  - In summer (EDT, UTC-4): scheduled_at = 18:00 UTC
- Both are correct — the user always sees "14:00" in their local time.

**Acceptance Criteria:**
- [ ] Account timezone stored as IANA string, validated against known timezone list
- [ ] Scheduler computes UTC scheduled_at using Timex with IANA timezone
- [ ] Test verifies correct UTC time for same wall-clock hour across DST boundary
- [ ] No UTC offsets stored anywhere in the system

**Safeguards:**
> ⚠️ Do not use `DateTime.from_naive!/2` with a fixed offset — always use a timezone-aware conversion via Timex or `DateTime.shift_zone!/2`.

**Notes:**
- `Timex` is already a project dependency. Use `Timex.is_valid_timezone?/1` for validation.
- Consider adding a `Kith.TimeHelper` module with `to_utc_scheduled_at(date, hour, timezone)` for reuse.

---

### TASK-06-13: Send-Hour Drift Behavior
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-06-08
**Description:**
Document and implement the accepted behavior when an account changes their `send_hour` setting.

**Behavior:**
- Already-enqueued Oban jobs fire at the old send hour. This is acceptable — up to 24-hour drift.
- The next nightly ReminderSchedulerWorker run enqueues new jobs at the new send hour.
- No re-enqueuing of existing jobs on send_hour change.

**UI requirement:** The Account Settings page (Phase 11) must display the notice: "Changing your send hour takes effect starting the following day."

**Acceptance Criteria:**
- [ ] Changing send_hour does NOT re-enqueue existing jobs
- [ ] Next scheduler run uses the new send_hour
- [ ] Settings UI displays the drift notice (coordinate with Phase 11)

**Notes:**
- This is intentionally simple. Re-enqueuing all jobs on send_hour change would add significant complexity for minimal benefit.

---

### TASK-06-14: Pre-Notification Sets
**Priority:** High
**Effort:** M
**Depends on:** TASK-06-02, TASK-06-08
**Description:**
Implement the pre-notification system for birthday and one-time reminders. Pre-notifications fire 30 days and 7 days before the actual reminder date.

**Behavior:**
- When scheduling a birthday or one-time reminder, check the account's active ReminderRules.
- For each active rule with `days_before > 0`, compute the pre-notification date: `next_reminder_date - days_before`.
- If the pre-notification date is in the future, enqueue an Oban job for it.
- Store ALL job IDs (30-day, 7-day, on-day) in `enqueued_oban_job_ids`.

**Cancellation triggers — ALL job IDs cancelled when:**
- Contact is archived
- Contact is soft-deleted
- Contact is merged (non-survivor)
- Reminder is deleted
- Reminder is edited (then re-enqueued with new dates)

**Acceptance Criteria:**
- [ ] Birthday reminders get up to 3 jobs: 30-day pre, 7-day pre, on-day
- [ ] One-time reminders get up to 3 jobs: 30-day pre, 7-day pre, on-day
- [ ] Stay-in-touch and recurring reminders get on-day only
- [ ] All job IDs stored in `enqueued_oban_job_ids`
- [ ] All cancellation triggers cancel ALL stored job IDs
- [ ] Disabled ReminderRules are respected (no job enqueued for disabled rules)

**Safeguards:**
> ⚠️ If a pre-notification date is in the past (e.g., reminder is 5 days away, so the 30-day and 7-day pre-notifications are past), do not enqueue those jobs. Only enqueue future-dated jobs.

**Notes:**
- Pre-notification emails have distinct subject lines indicating the countdown (see TASK-06-09).

---

### TASK-06-15: Upcoming Reminders Query
**Priority:** High
**Effort:** S
**Depends on:** TASK-06-01
**Description:**
Implement `Kith.Reminders.upcoming/2` — a query function that returns reminders due within a specified window.

**Signature:** `upcoming(%Scope{}, window_days)` where `window_days` is 30, 60, or 90.

**Query:**
```elixir
from r in Reminder,
  where: r.account_id == ^scope.account_id,
  where: r.active == true,
  where: r.next_reminder_date >= ^Date.utc_today(),
  where: r.next_reminder_date <= ^Date.add(Date.utc_today(), window_days),
  join: c in assoc(r, :contact),
  where: is_nil(c.deleted_at),
  where: is_nil(c.archived_at),
  where: c.deceased == false,
  order_by: [asc: r.next_reminder_date],
  preload: [:contact]
```

**Acceptance Criteria:**
- [ ] Returns reminders within the specified day window
- [ ] The query MUST filter: `contacts.deceased = false AND contacts.deleted_at IS NULL AND contacts.archived_at IS NULL`. Deceased, deleted, and archived contacts must not appear in the upcoming reminders list.
- [ ] Sorted by `next_reminder_date` ascending
- [ ] Preloads contact for display
- [ ] Scoped to account via `%Scope{}`

**Notes:**
- Used by both the Dashboard widget (count only: `upcoming/2 |> Repo.aggregate(:count)`) and the Upcoming Reminders page (full list).

---

### TASK-06-16: ReminderInstance Management (Resolve / Dismiss)
**Priority:** High
**Effort:** S
**Depends on:** TASK-06-01, TASK-06-05
**Description:**
Implement user actions on pending ReminderInstances: resolve and dismiss.

**`resolve_instance/1` (instance):**
- Set `status: :resolved`, `resolved_at: DateTime.utc_now()`
- For stay-in-touch reminders: update `reminder.next_reminder_date` to now + interval
- For other types: no additional action

**`dismiss_instance/1` (instance):**
- Set `status: :dismissed`, `resolved_at: DateTime.utc_now()`
- Same scheduling behavior as resolve (next fire after full interval)

**Acceptance Criteria:**
- [ ] Pending instances can be resolved or dismissed
- [ ] Resolved/dismissed stay-in-touch reminders re-fire after full interval
- [ ] Non-stay-in-touch resolved instances are terminal (one-time) or handled by scheduler (recurring)
- [ ] All roles can resolve/dismiss (viewer included — this is a notification action, not a data mutation)

**Notes:**
- No snooze in v1. Snooze is deferred to v1.5.

---

### TASK-06-17: Upcoming Reminders Page (LiveView)
**Priority:** High
**Effort:** M
**Depends on:** TASK-06-15, TASK-06-16
**Description:**
Implement the Upcoming Reminders page as a top-level LiveView accessible from the main navigation.

**UI elements:**
- Window selector: 30 / 60 / 90 days (tabs or dropdown)
- Reminder list sorted by date ascending
- Each row displays:
  - Contact name (linked to contact profile)
  - Reminder type with icon (birthday, stay-in-touch, one-time, recurring)
  - Due date (formatted via `ex_cldr`)
  - Type-specific icon
- Pending ReminderInstances show inline actions: "Mark resolved" and "Dismiss"
- Empty state message when no upcoming reminders

**Access:** All roles (admin, editor, viewer) can view and interact.

**Acceptance Criteria:**
- [ ] Page accessible from main nav
- [ ] 30/60/90-day window selector works
- [ ] Reminders listed with contact name, type, date
- [ ] Mark resolved / Dismiss actions work inline
- [ ] All roles can access
- [ ] Dates formatted via `ex_cldr`
- [ ] RTL-safe layout using Tailwind logical properties

**Safeguards:**
> ⚠️ Use `ex_cldr` for all date formatting — do not use raw `Calendar` or `Date.to_string/1`. This is a project-wide convention.

**Notes:**
- LiveView component hierarchy: `UpcomingRemindersLive` (Level 1) renders `ReminderRowComponent` (Level 3 function component) for each reminder.
- The window selector should update via LiveView navigation (URL param `?window=30`) so the selection is bookmarkable.

---

### TASK-06-18: Dashboard Reminder Widget
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-06-15
**Description:**
Add an upcoming reminders count widget to the Dashboard page.

**Display:** "X upcoming reminders" with a link to the Upcoming Reminders page. Shows count for 30-day window.

**Acceptance Criteria:**
- [ ] Dashboard shows count of upcoming reminders (30-day window)
- [ ] Count links to the Upcoming Reminders page
- [ ] All roles can see the widget
- [ ] Count updates when reminders are added/resolved/dismissed

**Notes:**
- This is a simple count query, not a full list. Use `Kith.Reminders.upcoming_count/1` backed by `Repo.aggregate(:count)`.

---

## E2E Product Tests

### TEST-06-01: Stay-in-Touch Resolution via Activity
**Type:** Browser (Playwright)
**Covers:** TASK-06-05, TASK-06-16

**Scenario:**
A stay-in-touch reminder fires, creating a pending instance. The user logs an Activity for the contact. The pending instance is automatically resolved, and the reminder re-fires after the full interval.

**Steps:**
1. Create a contact with a stay-in-touch reminder set to "monthly"
2. Advance time so the reminder fires (or directly create a pending ReminderInstance via factory)
3. Verify the Upcoming Reminders page shows a pending instance for this contact
4. Navigate to the contact profile and log a new Activity
5. Return to the Upcoming Reminders page

**Expected Outcome:**
The pending ReminderInstance is no longer shown (status changed to :resolved). The reminder's `next_reminder_date` has advanced by 30 days from today.

---

### TEST-06-02: Birthday Reminder Auto-Created on Birthdate Set
**Type:** Browser (Playwright)
**Covers:** TASK-06-04

**Scenario:**
Setting a birthdate on a contact automatically creates a birthday reminder.

**Steps:**
1. Create a new contact without a birthdate
2. Edit the contact and set birthdate to a future date (e.g., 2 months from now)
3. Navigate to the contact's reminders list

**Expected Outcome:**
A birthday reminder exists with `next_reminder_date` equal to the contact's birthday this year (or next year if already passed). The reminder type is "birthday".

---

### TEST-06-03: Birthday Reminder Cancelled on Birthdate Removal
**Type:** Browser (Playwright)
**Covers:** TASK-06-04

**Scenario:**
Removing a contact's birthdate deletes the associated birthday reminder.

**Steps:**
1. Create a contact with a birthdate set
2. Verify a birthday reminder exists
3. Edit the contact and clear the birthdate field
4. Check the contact's reminders list

**Expected Outcome:**
The birthday reminder no longer exists. No orphaned Oban jobs remain.

---

### TEST-06-04: February 29 Birthday in Non-Leap Year
**Type:** API (HTTP)
**Covers:** TASK-06-04

**Scenario:**
A contact born on February 29 has their birthday reminder fire on February 28 in non-leap years.

**Steps:**
1. Create a contact with birthdate 1996-02-29
2. Query the birthday reminder's `next_reminder_date`
3. If the current year is a non-leap year, verify the date is Feb 28 of the current (or next) year
4. If the current year is a leap year, verify the date is Feb 29

**Expected Outcome:**
`next_reminder_date` is Feb 28 in non-leap years and Feb 29 in leap years.

---

### TEST-06-05: DST Timezone Correctness
**Type:** API (HTTP)
**Covers:** TASK-06-12

**Scenario:**
A reminder scheduled at 14:00 America/New_York fires at the correct UTC time in both winter and summer.

**Steps:**
1. Set account timezone to "America/New_York" and send_hour to 14
2. Create a one-time reminder for a winter date (e.g., January 15)
3. Record the Oban job's `scheduled_at` UTC time
4. Create another one-time reminder for a summer date (e.g., July 15)
5. Record the Oban job's `scheduled_at` UTC time

**Expected Outcome:**
Winter reminder: `scheduled_at` is 19:00 UTC (14:00 + 5h EST offset). Summer reminder: `scheduled_at` is 18:00 UTC (14:00 + 4h EDT offset).

---

### TEST-06-06: Archive Contact Cancels Stay-in-Touch Jobs
**Type:** API (HTTP)
**Covers:** TASK-06-05

**Scenario:**
Archiving a contact cancels all stay-in-touch Oban jobs and dismisses pending instances.

**Steps:**
1. Create a contact with a stay-in-touch reminder (monthly)
2. Wait for or trigger the scheduler to enqueue jobs
3. Verify Oban jobs exist (check `enqueued_oban_job_ids` is non-empty)
4. Archive the contact via API
5. Query the Oban jobs table for the stored job IDs

**Expected Outcome:**
All Oban jobs are in `cancelled` state. Any pending ReminderInstance has `status: :dismissed`. The reminder has `active: false`.

---

### TEST-06-07: Send-Hour Change Behavior
**Type:** API (HTTP)
**Covers:** TASK-06-13

**Scenario:**
Changing the account's send_hour does not re-enqueue existing jobs but affects new ones.

**Steps:**
1. Set account send_hour to 10, timezone to "America/New_York"
2. Create a one-time reminder for tomorrow
3. Record the Oban job's `scheduled_at` (should be 10:00 New York time in UTC)
4. Change account send_hour to 16
5. Verify the existing Oban job's `scheduled_at` is unchanged
6. Create another one-time reminder for the day after tomorrow
7. Record the new Oban job's `scheduled_at`

**Expected Outcome:**
First job retains old scheduled_at (10:00 NY). Second job is scheduled at 16:00 NY time (in UTC).

---

### TEST-06-08: ReminderSchedulerWorker Idempotency
**Type:** API (HTTP)
**Covers:** TASK-06-08

**Scenario:**
Running the ReminderSchedulerWorker twice within 24 hours does not double-enqueue jobs.

**Steps:**
1. Create a one-time reminder due tomorrow
2. Run ReminderSchedulerWorker manually (via `perform/1`)
3. Record the number of Oban jobs for this reminder
4. Run ReminderSchedulerWorker again
5. Record the number of Oban jobs for this reminder

**Expected Outcome:**
The job count is identical after both runs. `enqueued_oban_job_ids` contains the same IDs.

---

### TEST-06-09: ReminderNotificationWorker Sends Email
**Type:** API (HTTP)
**Covers:** TASK-06-09

**Scenario:**
The ReminderNotificationWorker sends an email and creates a pending ReminderInstance.

**Steps:**
1. Create a contact with a one-time reminder
2. Directly invoke `ReminderNotificationWorker.perform/1` with the reminder's job args
3. Check the Swoosh test mailbox for the notification email
4. Query ReminderInstances for this reminder

**Expected Outcome:**
One email sent with correct subject line. One ReminderInstance with `status: :pending` and `fired_at` set.

---

### TEST-06-10: Pre-Notification for Birthday Reminder
**Type:** API (HTTP)
**Covers:** TASK-06-14

**Scenario:**
A birthday reminder enqueues 30-day, 7-day, and on-day notification jobs.

**Steps:**
1. Ensure account has all three ReminderRules active (30, 7, 0 days)
2. Create a contact with birthdate 45 days from now
3. Run ReminderSchedulerWorker
4. Query `enqueued_oban_job_ids` on the birthday reminder

**Expected Outcome:**
Three Oban job IDs stored. Jobs are scheduled for: birthday - 30 days, birthday - 7 days, and birthday date — all at the account's send_hour in UTC.

---

### TEST-06-11: ContactPurgeWorker Hard-Deletes Stale Contacts
**Type:** API (HTTP)
**Covers:** TASK-06-11

**Scenario:**
A contact soft-deleted more than 30 days ago is permanently hard-deleted.

**Steps:**
1. Create a contact and soft-delete it
2. Manually backdate `deleted_at` to 31 days ago (via direct DB update in test)
3. Run ContactPurgeWorker manually
4. Query the contacts table for this contact (including soft-deleted)

**Expected Outcome:**
Contact does not exist in the database (hard-deleted). All sub-entities (notes, activities, etc.) are also gone (CASCADE). An audit log entry exists with the contact's name and "permanently purged" message.

---

### TEST-06-12: Upcoming Reminders Page Windows
**Type:** Browser (Playwright)
**Covers:** TASK-06-17

**Scenario:**
The Upcoming Reminders page correctly filters by 30, 60, and 90-day windows.

**Steps:**
1. Create three contacts with reminders due in 15, 45, and 75 days respectively
2. Navigate to Upcoming Reminders page with 30-day window
3. Note the count
4. Switch to 60-day window
5. Note the count
6. Switch to 90-day window
7. Note the count

**Expected Outcome:**
30-day window: 1 reminder. 60-day window: 2 reminders. 90-day window: 3 reminders. Each window shows the correct reminders sorted by date.

---

## Phase Safeguards

1. **Ecto.Multi everywhere:** Every reminder mutation (create, update, delete) must use `Ecto.Multi` to ensure Oban job management is transactional with the DB change. No bare `Repo.insert/update/delete` calls for reminders.

2. **Oban.cancel_job is not transactional:** Cancellation happens outside the Ecto transaction. Cancel FIRST, then proceed with the DB change. A cancelled-but-orphaned job is harmless; an un-cancelled job firing on stale data is not.

3. **Cross-context calls:** The Reminders context is called from:
   - Contacts context (birthday auto-creation, archival, soft-delete, merge)
   - Interactions context (stay-in-touch resolution via Activity/Call)
   These calls must be within the caller's `Ecto.Multi`, not as separate transactions.

4. **No Postgres enums:** Use string columns with Ecto changeset validation for `type`, `status`, and `frequency`. This avoids migration pain when adding new values.

5. **DST correctness:** Always compute UTC from IANA timezone at scheduling time. Never cache or store UTC offsets.

6. **Idempotency:** ReminderSchedulerWorker must be safe to run multiple times. The `enqueued_oban_job_ids` check prevents double-enqueuing.

## Phase Notes

1. **Oban cron configuration** should be centralized in `config/config.exs`:
   ```elixir
   config :kith, Oban,
     queues: [default: 10, reminders: 5, maintenance: 2, exports: 2, integrations: 2],
     plugins: [
       {Oban.Plugins.Cron, crontab: [
         {"0 0 * * *", Kith.Workers.ReminderSchedulerWorker, queue: :reminders},
         {"0 1 * * *", Kith.Workers.ContactPurgeWorker, queue: :maintenance}
       ]}
     ]
   ```

2. **Oban transactional enqueue pattern** (pre-code gate confirmation):
   ```elixir
   Ecto.Multi.new()
   |> Ecto.Multi.insert(:reminder, changeset)
   |> Ecto.Multi.run(:enqueue_jobs, fn repo, %{reminder: reminder} ->
     jobs = build_notification_jobs(reminder, account)
     {_count, oban_jobs} = Oban.insert_all(jobs)
     job_ids = Enum.map(oban_jobs, & &1.id)
     reminder
     |> Ecto.Changeset.change(%{enqueued_oban_job_ids: job_ids})
     |> repo.update()
   end)
   |> Repo.transaction()
   ```

3. **Testing Oban workers:** Use `Oban.Testing` module. In tests, configure `Oban` with `testing: :manual` mode. Use `assert_enqueued/1` and `refute_enqueued/1` to verify job scheduling. Use `Oban.drain_queue/1` to synchronously execute jobs in tests.

4. **Email templates:** Keep reminder notification emails simple in v1. Plain text + minimal HTML. Use Swoosh's built-in template support. Emails should include: reminder type, contact name, due date, and a link to the contact in Kith.

5. **Timex vs. standard library:** Elixir 1.17+ has improved `DateTime` timezone support. However, `Timex` is already a project dependency and provides more ergonomic DST handling. Use Timex consistently for all timezone operations in this phase.

6. **Contact merge impact:** When contacts are merged (Phase 04), the non-survivor's reminders are cancelled (Oban jobs) and deleted. The survivor's reminders are unaffected. Birthday reminders are NOT merged — if the survivor already has a birthday reminder, the non-survivor's is simply deleted.

7. **Oban transactional safety guarantee:** `Oban.insert/3` and `Oban.insert_all/3` when used within an `Ecto.Multi` participate in the same database transaction. If the Multi rolls back, the Oban job rows are also rolled back — they are never visible to the Oban queue. This is the fundamental guarantee that makes the `enqueued_oban_job_ids` design safe. Phase 14 (QA) includes TEST-14-16 to verify this property explicitly. Note: `Oban.cancel_job/1` does NOT participate in the Multi transaction — it is a separate DB update (see Phase Safeguard #2).

8. **Immich circuit breaker pattern divergence:** The ImmichSyncWorker (Phase 07) does NOT use Oban's built-in retry/max_attempts for circuit breaking. Instead, it uses a per-account DB counter (`account.immich_consecutive_failures`). The worker always returns `:ok` from Oban's perspective and handles errors internally per-account. This is a different pattern from ReminderNotificationWorker, which uses Oban's native retry (max 3 attempts, exponential backoff). Both patterns are valid — Immich needs per-account circuit breaking, while reminder notifications need per-job retries.

9. **DataExportWorker (Phase 09):** The `exports` queue (concurrency: 2) is reserved for `Kith.Workers.DataExportWorker`, implemented in Phase 09. For large accounts (>1000 contacts), the POST /api/export endpoint (Phase 10, TASK-10-36) enqueues an export job rather than responding synchronously. The worker generates the full JSON export, stores the file via `Kith.Storage`, and sends a `DataExportReadyEmail` via Swoosh. The API returns `{status: "processing", job_id: "..."}` for polling.
