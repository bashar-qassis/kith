# Phase 06 Gap Analysis

## Coverage Summary
Phase 06 comprehensively covers the core reminder system with strong alignment to the product spec. All four reminder types (birthday, stay-in-touch, one-time, recurring) are defined with proper task structure. Key technical requirements around DST, Feb 29, Oban transactionality, and idempotency are explicitly documented. Minor gaps exist around cross-phase coordination, failure handling, and deceased contact guards.

## Gaps Found

1. **ReminderInstance field naming inconsistency: `fired_at` vs `triggered_at` (MEDIUM)**
   - What's missing: Phase 03 migration spec names the field `triggered_at`; Phase 06 refers to `fired_at`
   - Spec reference: TASK-06-01 (Phase 06) vs TASK-03-07 (Phase 03)
   - Impact: Schema mismatch could cause implementation errors

2. **Contact merge reminder handling not covered (MEDIUM)**
   - What's missing: Product spec mentions reminder job cancellation during contact merge, but Phase 06 has no task or test for merge-triggered cancellation. Also no coverage of contact restore/unarchive reminder re-enablement.
   - Spec reference: Section 2 (v1 Feature Scope, #11 — Contact Merge)
   - Impact: Contact operations may orphan reminders or Oban jobs

3. **Stay-in-touch resolution via Activity/Call — no cross-phase verification (MEDIUM)**
   - What's missing: Phase 06 TASK-06-05 requires Activity/Call to call `resolve_stay_in_touch_instance/1` in same Ecto.Multi, but Phase 06 includes no verification that Phase 03 (Interactions context) correctly implemented this
   - Spec reference: Section 7 (Stay-in-Touch Semantics)
   - Impact: If Activity/Call creation omits the Multi call, stay-in-touch reminders re-enqueue prematurely

4. **Missing ReminderInstance `failed` status handling (MEDIUM)**
   - What's missing: Phase 06 TASK-06-01 defines four statuses (pending, resolved, dismissed, failed) but no task or test covers what triggers `failed` status or how ReminderNotificationWorker handles failures
   - Spec reference: Product spec does not detail failure recovery semantics
   - Impact: Worker error handling path unclear

5. **Deceased contact guard not in Phase 06 (LOW)**
   - What's missing: Phase 04 TASK-04-04 explicitly requires a deceased contact suppression guard in ReminderNotificationWorker, but Phase 06 does not reference this requirement or include a test
   - Spec reference: Section 7 (implied by deceased flag behavior)
   - Impact: Deceased contacts may still receive reminder notifications

6. **Upcoming reminders query — deceased filter missing (LOW)**
   - What's missing: Phase 06 TASK-06-15 excludes archived/soft-deleted contacts from the upcoming reminders query but does NOT mention the `deceased` filter
   - Spec reference: Product spec does not explicitly clarify; implied by deceased flag behavior
   - Impact: Dashboard may show reminders for deceased contacts

7. **Notification email template/content not specified (LOW)**
   - What's missing: Phase 06 assumes email sending works but does not define email subject, body, or template structure
   - Spec reference: Product spec is also silent on email format
   - Impact: Implementation will require assumptions; consistency risk across developers

8. **ReminderRules `active` toggle — on-day rule deletion safeguard implementation unclear (LOW)**
   - What's missing: Phase 06 TASK-06-02 says "on-day rule should not be deletable" but implementation strategy is unclear; no test covers attempting to delete the 0-day rule
   - Impact: Users could accidentally disable all notifications

9. **Pre-notification job batching not specified (LOW)**
   - What's missing: Phase 06 TASK-06-08 mentions "batching accounts" but does not define how multiple jobs per reminder are created atomically or the expected ordering
   - Impact: Unlikely production issue but ordering assumptions could affect test flakiness

10. **ReminderNotificationWorker test — `fired_at` timestamp not verified (LOW)**
    - What's missing: TEST-06-09 only checks email send and `status: :pending`; does not verify `fired_at` timestamp assignment
    - Impact: Coverage gap

## No Gaps / Well Covered

- All four reminder types fully implemented: birthday, stay-in-touch, one-time, recurring — each with dedicated tasks and clear semantics
- Stay-in-touch pending block semantics: TASK-06-05 explicitly documents "no re-enqueue while pending" logic
- Pre-notification windows: 30-day, 7-day, on-day for birthday/one-time; stay-in-touch/recurring on-day only
- `enqueued_oban_job_ids` tracking: all three IDs stored, referenced in TASK-06-14 and TEST-06-10
- DST handling: IANA timezone names required, Timex for UTC conversion, UTC offsets forbidden (TASK-06-12)
- Feb 29 handling: non-leap year fallback to Feb 28 (TASK-06-04 and TEST-06-04)
- Oban job cancellation always inside Ecto.Multi: confirmed by Phase 00 TASK-00-03 pseudocode covering all 7 operations
- ReminderSchedulerWorker idempotence: "skip if enqueued_oban_job_ids not empty" guard (TASK-06-08); TEST-06-08 verifies no double-enqueue
