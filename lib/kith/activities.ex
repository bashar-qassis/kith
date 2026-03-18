defmodule Kith.Activities do
  @moduledoc """
  The Activities context — activities, life events, and calls.
  """

  import Ecto.Query, warn: false
  import Kith.Scope

  alias Kith.Repo
  alias Kith.Activities.{Activity, LifeEvent, Call}

  ## Activities

  def list_activities(account_id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [:contacts, :emotions])

    Activity
    |> scope_to_account(account_id)
    |> Repo.all()
    |> Repo.preload(preloads)
  end

  def list_activities_for_contact(contact_id) do
    from(a in Activity,
      join: ac in "activity_contacts",
      on: ac.activity_id == a.id,
      where: ac.contact_id == ^contact_id
    )
    |> Repo.all()
  end

  def get_activity!(account_id, id) do
    Activity
    |> scope_to_account(account_id)
    |> Repo.get!(id)
  end

  def create_activity(account_id, attrs, contact_ids \\ [], emotion_ids \\ []) do
    %Activity{account_id: account_id}
    |> Activity.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, activity} ->
        now = DateTime.utc_now(:second)

        if contact_ids != [] do
          contact_entries =
            Enum.map(contact_ids, fn cid ->
              %{activity_id: activity.id, contact_id: cid, inserted_at: now, updated_at: now}
            end)

          Repo.insert_all("activity_contacts", contact_entries)
        end

        if emotion_ids != [] do
          emotion_entries =
            Enum.map(emotion_ids, fn eid ->
              %{activity_id: activity.id, emotion_id: eid, inserted_at: now, updated_at: now}
            end)

          Repo.insert_all("activity_emotions", emotion_entries)
        end

        {:ok, activity}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_activity(%Activity{} = activity, attrs) do
    activity
    |> Activity.changeset(attrs)
    |> Repo.update()
  end

  def delete_activity(%Activity{} = activity) do
    Repo.delete(activity)
  end

  ## Life Events

  def list_life_events(contact_id) do
    from(le in LifeEvent, where: le.contact_id == ^contact_id)
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
    |> Repo.preload(:emotion)
  end

  def get_call!(account_id, id) do
    Call
    |> scope_to_account(account_id)
    |> Repo.get!(id)
  end

  def create_call(%{account_id: account_id, id: contact_id} = _contact, attrs) do
    %Call{contact_id: contact_id, account_id: account_id}
    |> Call.changeset(attrs)
    |> Repo.insert()
  end

  def update_call(%Call{} = call, attrs) do
    call
    |> Call.changeset(attrs)
    |> Repo.update()
  end

  def delete_call(%Call{} = call) do
    Repo.delete(call)
  end
end
