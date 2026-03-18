defmodule Kith.Activities do
  @moduledoc """
  The Activities context — activities, life events, and calls.

  Activity and call creation use Ecto.Multi to transactionally update
  `last_talked_to` on all involved contacts.
  """

  import Ecto.Query, warn: false
  import Kith.Scope

  alias Ecto.Multi
  alias Kith.Repo
  alias Kith.Contacts.Contact
  alias Kith.Activities.{Activity, LifeEvent, Call}

  ## Activities

  def list_activities(account_id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [:contacts, :emotions])

    Activity
    |> scope_to_account(account_id)
    |> order_by([a], desc: a.occurred_at)
    |> Repo.all()
    |> Repo.preload(preloads)
  end

  def list_activities_for_contact(contact_id) do
    from(a in Activity,
      join: ac in "activity_contacts",
      on: ac.activity_id == a.id,
      where: ac.contact_id == ^contact_id,
      order_by: [desc: a.occurred_at]
    )
    |> Repo.all()
    |> Repo.preload([:contacts, :emotions])
  end

  def get_activity!(account_id, id) do
    Activity
    |> scope_to_account(account_id)
    |> Repo.get!(id)
    |> Repo.preload([:contacts, :emotions])
  end

  @doc """
  Creates an activity within an Ecto.Multi transaction:
  1. Insert the activity
  2. Insert activity_contacts join records
  3. Insert activity_emotions join records
  4. Update last_talked_to for all involved contacts
  """
  def create_activity(account_id, attrs, contact_ids \\ [], emotion_ids \\ []) do
    Multi.new()
    |> Multi.insert(:activity, fn _changes ->
      %Activity{account_id: account_id}
      |> Activity.changeset(attrs)
    end)
    |> Multi.run(:contacts, fn repo, %{activity: activity} ->
      if contact_ids != [] do
        entries =
          Enum.map(contact_ids, fn cid ->
            %{activity_id: activity.id, contact_id: cid}
          end)

        {count, _} = repo.insert_all("activity_contacts", entries)
        {:ok, count}
      else
        {:ok, 0}
      end
    end)
    |> Multi.run(:emotions, fn repo, %{activity: activity} ->
      if emotion_ids != [] do
        entries =
          Enum.map(emotion_ids, fn eid ->
            %{activity_id: activity.id, emotion_id: eid}
          end)

        {count, _} = repo.insert_all("activity_emotions", entries)
        {:ok, count}
      else
        {:ok, 0}
      end
    end)
    |> Multi.run(:update_last_talked_to, fn repo, %{activity: activity} ->
      if contact_ids != [] do
        from(c in Contact,
          where: c.id in ^contact_ids,
          where: is_nil(c.last_talked_to) or c.last_talked_to < ^activity.occurred_at
        )
        |> repo.update_all(set: [last_talked_to: activity.occurred_at])
      end

      {:ok, :updated}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{activity: activity}} -> {:ok, Repo.preload(activity, [:contacts, :emotions])}
      {:error, :activity, changeset, _} -> {:error, changeset}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def update_activity(%Activity{} = activity, attrs, contact_ids \\ nil, emotion_ids \\ nil) do
    Multi.new()
    |> Multi.update(:activity, Activity.changeset(activity, attrs))
    |> Multi.run(:update_contacts, fn repo, %{activity: updated} ->
      if contact_ids do
        # Remove old join records, insert new ones
        from(ac in "activity_contacts", where: ac.activity_id == ^updated.id)
        |> repo.delete_all()

        if contact_ids != [] do
          entries = Enum.map(contact_ids, fn cid -> %{activity_id: updated.id, contact_id: cid} end)
          repo.insert_all("activity_contacts", entries)
        end

        # Update last_talked_to for new set of contacts
        from(c in Contact,
          where: c.id in ^contact_ids,
          where: is_nil(c.last_talked_to) or c.last_talked_to < ^updated.occurred_at
        )
        |> repo.update_all(set: [last_talked_to: updated.occurred_at])
      end

      {:ok, :done}
    end)
    |> Multi.run(:update_emotions, fn repo, %{activity: updated} ->
      if emotion_ids do
        from(ae in "activity_emotions", where: ae.activity_id == ^updated.id)
        |> repo.delete_all()

        if emotion_ids != [] do
          entries = Enum.map(emotion_ids, fn eid -> %{activity_id: updated.id, emotion_id: eid} end)
          repo.insert_all("activity_emotions", entries)
        end
      end

      {:ok, :done}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{activity: activity}} -> {:ok, Repo.preload(activity, [:contacts, :emotions], force: true)}
      {:error, :activity, changeset, _} -> {:error, changeset}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def delete_activity(%Activity{} = activity) do
    Repo.delete(activity)
  end

  ## Life Events

  def list_life_events(contact_id) do
    from(le in LifeEvent,
      where: le.contact_id == ^contact_id,
      order_by: [desc: le.occurred_on]
    )
    |> Repo.all()
    |> Repo.preload(:life_event_type)
  end

  def get_life_event!(account_id, id) do
    LifeEvent
    |> scope_to_account(account_id)
    |> Repo.get!(id)
  end

  def create_life_event(%{account_id: account_id, id: contact_id} = _contact, attrs) do
    %LifeEvent{contact_id: contact_id, account_id: account_id}
    |> LifeEvent.changeset(attrs)
    |> Repo.insert()
  end

  def update_life_event(%LifeEvent{} = life_event, attrs) do
    life_event
    |> LifeEvent.changeset(attrs)
    |> Repo.update()
  end

  def delete_life_event(%LifeEvent{} = life_event) do
    Repo.delete(life_event)
  end

  ## Calls

  def list_calls(contact_id) do
    from(c in Call,
      where: c.contact_id == ^contact_id,
      order_by: [desc: c.occurred_at]
    )
    |> Repo.all()
    |> Repo.preload([:emotion, :call_direction])
  end

  def get_call!(account_id, id) do
    Call
    |> scope_to_account(account_id)
    |> Repo.get!(id)
    |> Repo.preload([:emotion, :call_direction])
  end

  @doc """
  Creates a call within an Ecto.Multi transaction:
  1. Insert the call
  2. Update last_talked_to for the contact
  """
  def create_call(%{account_id: account_id, id: contact_id} = _contact, attrs) do
    Multi.new()
    |> Multi.insert(:call, fn _changes ->
      %Call{contact_id: contact_id, account_id: account_id}
      |> Call.changeset(attrs)
    end)
    |> Multi.run(:update_last_talked_to, fn repo, %{call: call} ->
      from(c in Contact,
        where: c.id == ^contact_id,
        where: is_nil(c.last_talked_to) or c.last_talked_to < ^call.occurred_at
      )
      |> repo.update_all(set: [last_talked_to: call.occurred_at])

      {:ok, :updated}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{call: call}} -> {:ok, Repo.preload(call, [:emotion, :call_direction])}
      {:error, :call, changeset, _} -> {:error, changeset}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  def update_call(%Call{} = call, attrs) do
    call
    |> Call.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, [:emotion, :call_direction], force: true)}
      error -> error
    end
  end

  def delete_call(%Call{} = call) do
    Repo.delete(call)
  end
end
