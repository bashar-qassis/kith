# ADR-03: Oban Transactionality

## Overview

Every Oban job insertion and cancellation in Kith **must** occur inside the same `Ecto.Multi` transaction as the data mutation it belongs to. If any step in the pipeline fails, the entire transaction rolls back — no orphaned jobs fire for data that was never written, and no missing jobs leave data without a scheduled action.

This guarantee is enforced via two patterns:

- **`Oban.insert/4` multi adapter** — when the job insertion is straightforward and does not depend on data produced earlier in the same Multi.
- **`Multi.run/3`** — when job insertion or cancellation requires data produced by a prior Multi step (e.g., the newly-inserted reminder's ID), or when multiple jobs must be inserted in a loop with error aggregation.

The `reminders` table carries an `enqueued_oban_job_ids` jsonb column (default `[]`) that records the Oban job IDs associated with each reminder. This column is always updated within the same Multi that creates or cancels the jobs.

---

## Oban Multi Integration

```elixir
# Pattern A — direct multi adapter (simple, single job)
multi
|> Oban.insert(:job_name, MyWorker.new(args))

# Pattern B — Multi.run (multiple jobs, loops, or data-dependent args)
multi
|> Multi.run(:oban_jobs, fn _repo, %{reminder: reminder} ->
  jobs =
    build_job_changesets(reminder)
    |> Enum.map(&Oban.insert!(&1))   # all inside the open transaction
  {:ok, jobs}
end)

# Cancellation always goes through Multi.run
multi
|> Multi.run(:cancel_jobs, fn _repo, _ ->
  ids
  |> Enum.each(&Oban.cancel_job/1)
  {:ok, :cancelled}
end)
```

`Oban.insert!/1` called inside `Multi.run/3` participates in the ambient database transaction because Oban uses the same PostgreSQL connection. If the transaction rolls back, the inserted `oban_jobs` rows are rolled back with it.

---

## Pre-notification Strategy

Birthday and one-time reminders produce **three Oban jobs** per reminder:

| Job | Offset |
|-----|--------|
| 30-day-before | fire\_date − 30 days |
| 7-day-before  | fire\_date − 7 days  |
| on-day        | fire\_date            |

All three job IDs are stored in `enqueued_oban_job_ids`. Stay-in-touch and recurring reminders produce a **single job** per reminder.

---

## DST Handling

Always store and compute fire dates using IANA timezone names (e.g., `"America/New_York"`). Use **Timex** to convert to UTC before scheduling. Never store UTC offsets — they change across DST boundaries and will produce incorrect fire times.

---

## Feb 29 Rule

When a birthday falls on February 29, fire on **February 28** in non-leap years.

---

## Operation 1: Reminder Create

```elixir
Ecto.Multi.new()
|> Multi.insert(:reminder, reminder_changeset)
|> Multi.run(:oban_jobs, fn _repo, %{reminder: reminder} ->
  jobs = build_jobs_for_reminder(reminder)   # 1 or 3 changesets depending on type
  inserted = Enum.map(jobs, &Oban.insert!/1)
  {:ok, inserted}
end)
|> Multi.update(:update_job_ids, fn %{reminder: r, oban_jobs: jobs} ->
  ids = Enum.map(jobs, & &1.id)
  Reminder.changeset(r, %{enqueued_oban_job_ids: ids})
end)
|> Repo.transaction()
```

**Failure:** entire Multi rolls back. No reminder row exists, no Oban jobs are enqueued.

---

## Operation 2: Reminder Update

```elixir
Ecto.Multi.new()
|> Multi.run(:cancel_old_jobs, fn _repo, _ ->
  Enum.each(reminder.enqueued_oban_job_ids, &Oban.cancel_job/1)
  {:ok, :cancelled}
end)
|> Multi.update(:reminder, updated_changeset)
|> Multi.run(:new_oban_jobs, fn _repo, %{reminder: reminder} ->
  jobs = build_jobs_for_reminder(reminder)
  inserted = Enum.map(jobs, &Oban.insert!/1)
  {:ok, inserted}
end)
|> Multi.update(:update_job_ids, fn %{reminder: r, new_oban_jobs: jobs} ->
  ids = Enum.map(jobs, & &1.id)
  Reminder.changeset(r, %{enqueued_oban_job_ids: ids})
end)
|> Repo.transaction()
```

**Failure:** rolls back. Old jobs are **not** cancelled (the cancellation rolled back too). Reminder is unchanged.

---

## Operation 3: Reminder Delete

```elixir
Ecto.Multi.new()
|> Multi.run(:cancel_jobs, fn _repo, _ ->
  Enum.each(reminder.enqueued_oban_job_ids, &Oban.cancel_job/1)
  {:ok, :cancelled}
end)
|> Multi.delete(:reminder, reminder)
|> Repo.transaction()
```

**Failure:** rolls back. Jobs remain active, reminder remains in the database.

---

## Operation 4: Contact Archive

```elixir
Ecto.Multi.new()
|> Multi.run(:cancel_all_reminder_jobs, fn _repo, _ ->
  active_reminders_for(contact)
  |> Enum.flat_map(& &1.enqueued_oban_job_ids)
  |> Enum.each(&Oban.cancel_job/1)
  {:ok, :cancelled}
end)
|> Multi.update_all(:deactivate_reminders,
  reminders_query_for(contact),
  set: [active: false, enqueued_oban_job_ids: []]
)
|> Multi.update(:archive_contact, Contact.changeset(contact, %{archived: true}))
|> Repo.transaction()
```

**Note:** Unarchiving a contact does **not** automatically re-enable reminders or re-enqueue jobs. The user must re-enable reminders explicitly.

**Failure:** rolls back. Contact is not archived, reminders remain active with their original job IDs.

---

## Operation 5: Contact Soft-Delete

```elixir
Ecto.Multi.new()
|> Multi.run(:cancel_all_reminder_jobs, fn _repo, _ ->
  active_reminders_for(contact)
  |> Enum.flat_map(& &1.enqueued_oban_job_ids)
  |> Enum.each(&Oban.cancel_job/1)
  {:ok, :cancelled}
end)
|> Multi.update_all(:deactivate_reminders,
  reminders_query_for(contact),
  set: [active: false, enqueued_oban_job_ids: []]
)
|> Multi.update(:soft_delete_contact,
  Contact.changeset(contact, %{deleted_at: DateTime.utc_now()})
)
|> Repo.transaction()
```

**Failure:** rolls back entirely. `deleted_at` is not set, reminders remain active.

---

## Operation 6: Contact Merge (non-survivor cleanup)

```elixir
Ecto.Multi.new()
|> Multi.run(:cancel_nonsurvivor_jobs, fn _repo, _ ->
  reminders_for(non_survivor)
  |> Enum.flat_map(& &1.enqueued_oban_job_ids)
  |> Enum.each(&Oban.cancel_job/1)
  {:ok, :cancelled}
end)
|> Multi.update_all(:remap_sub_entities,
  sub_entities_query_for(non_survivor),
  set: [contact_id: survivor.id]
)
|> Multi.update_all(:remap_kept_reminders,
  reminders_query_for(non_survivor),
  set: [contact_id: survivor.id, enqueued_oban_job_ids: []]
)
|> Multi.run(:enqueue_survivor_jobs, fn _repo, _ ->
  remapped_reminders_for(survivor)
  |> Enum.map(fn r ->
    jobs = build_jobs_for_reminder(r)
    inserted = Enum.map(jobs, &Oban.insert!/1)
    {r.id, inserted}
  end)
  |> then(&{:ok, &1})
end)
|> Multi.run(:update_remapped_job_ids, fn _repo, %{enqueue_survivor_jobs: pairs} ->
  Enum.each(pairs, fn {reminder_id, jobs} ->
    ids = Enum.map(jobs, & &1.id)
    Repo.update_all(
      from(r in Reminder, where: r.id == ^reminder_id),
      set: [enqueued_oban_job_ids: ids]
    )
  end)
  {:ok, :updated}
end)
|> Multi.run(:deduplicate_relationships, fn _repo, _ ->
  deduplicate_relationships_for(survivor)
  {:ok, :deduped}
end)
|> Multi.update(:soft_delete_nonsurvivor,
  Contact.changeset(non_survivor, %{deleted_at: DateTime.utc_now()})
)
|> Repo.transaction()
```

**Failure:** entire merge rolls back. Both contacts are unchanged. Non-survivor is not soft-deleted.

---

## Operation 7: Stay-in-Touch Reset (Activity or Call Logged)

When an Activity or Call is logged involving contacts that have a pending stay-in-touch reminder:

```elixir
Ecto.Multi.new()
|> Multi.insert(:activity_or_call, changeset)
|> Multi.update_all(:update_last_talked_to,
  contacts_query_for(involved_contact_ids),
  set: [last_talked_to: DateTime.utc_now()]
)
|> Multi.run(:resolve_stay_in_touch, fn _repo, _ ->
  involved_contacts
  |> Enum.each(fn contact ->
    case pending_stay_in_touch_instance(contact) do
      nil -> :ok
      instance ->
        Enum.each(instance.reminder.enqueued_oban_job_ids, &Oban.cancel_job/1)
        resolve_reminder_instance(instance)
    end
  end)
  {:ok, :resolved}
end)
|> Multi.run(:reschedule_stay_in_touch, fn _repo, _ ->
  involved_contacts
  |> Enum.map(fn contact ->
    case stay_in_touch_reminder(contact) do
      nil -> :skip
      reminder ->
        next_date = compute_next_fire_date(reminder, DateTime.utc_now())
        job = StayInTouchWorker.new(%{reminder_id: reminder.id}, scheduled_at: next_date)
        inserted = Oban.insert!(job)
        {reminder.id, inserted}
    end
  end)
  |> Enum.reject(&(&1 == :skip))
  |> then(&{:ok, &1})
end)
|> Multi.run(:update_job_ids, fn _repo, %{reschedule_stay_in_touch: pairs} ->
  Enum.each(pairs, fn {reminder_id, job} ->
    Repo.update_all(
      from(r in Reminder, where: r.id == ^reminder_id),
      set: [enqueued_oban_job_ids: [job.id]]
    )
  end)
  {:ok, :updated}
end)
|> Repo.transaction()
```

**Failure:** activity/call is not saved. No reminder instances are resolved, no jobs are cancelled or rescheduled.

---

## Failure Guarantees

| Scenario | Outcome |
|----------|---------|
| Job insertion fails mid-Multi | Full rollback — data mutation does not persist |
| Job cancellation fails mid-Multi | Full rollback — data mutation does not persist |
| Database constraint violation | Full rollback — no partial state, no orphaned jobs |
| Process crash before `Repo.transaction/1` returns | PostgreSQL rolls back automatically |

Because Oban jobs are stored in PostgreSQL (`oban_jobs` table), they participate in the same ACID transaction as all other Ecto operations. There is no "two-phase commit" risk between the application database and a separate job store.

---

## ADR-03 Enforcement Rule

> **Every `Oban.insert` (and `Oban.insert!`) call in the Kith codebase MUST be inside an `Ecto.Multi` pipeline.**

Standalone `Oban.insert` calls outside of a Multi are a **merge-blocking violation**. They create a race condition where the job can be enqueued but the associated data mutation can subsequently fail (or vice versa), leading to orphaned jobs or silently missing notifications.

Code review checklist item: search for `Oban.insert` not preceded by a Multi step before merging any PR that touches reminders, contacts, activities, or calls.

```
# Forbidden — standalone insert outside Multi
def create_reminder(attrs) do
  with {:ok, reminder} <- Repo.insert(changeset) do
    Oban.insert(ReminderWorker.new(%{id: reminder.id}))  # VIOLATION
  end
end

# Required — insert inside Multi
def create_reminder(attrs) do
  Ecto.Multi.new()
  |> Multi.insert(:reminder, changeset)
  |> Multi.run(:oban_jobs, fn _repo, %{reminder: r} ->
    {:ok, [Oban.insert!(ReminderWorker.new(%{id: r.id}))]}
  end)
  |> Multi.update(:update_job_ids, ...)
  |> Repo.transaction()
end
```
