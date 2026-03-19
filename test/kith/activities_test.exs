defmodule Kith.ActivitiesTest do
  use Kith.DataCase, async: true

  alias Kith.Activities

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup do
    seed_reference_data!()
    user = user_fixture()
    account_id = user.account_id
    contact = contact_fixture(account_id)
    %{user: user, account_id: account_id, contact: contact}
  end

  ## Activities

  describe "activities" do
    test "create_activity/4 with contacts and emotions", %{
      contact: contact,
      account_id: account_id
    } do
      emotions = Kith.Contacts.list_emotions(account_id)
      emotion_ids = Enum.map(Enum.take(emotions, 1), & &1.id)

      {:ok, activity} =
        Activities.create_activity(
          account_id,
          %{"title" => "Lunch", "occurred_at" => "2026-03-15T12:00"},
          [contact.id],
          emotion_ids
        )

      assert activity.title == "Lunch"

      activities = Activities.list_activities_for_contact(contact.id)
      assert length(activities) == 1
      assert hd(activities).title == "Lunch"
      assert length(hd(activities).contacts) == 1
      assert length(hd(activities).emotions) == 1
    end

    test "create_activity/4 updates last_talked_to", %{
      contact: contact,
      account_id: account_id
    } do
      {:ok, _} =
        Activities.create_activity(
          account_id,
          %{"title" => "Chat", "occurred_at" => "2026-03-15T12:00"},
          [contact.id],
          []
        )

      updated = Kith.Contacts.get_contact!(account_id, contact.id)
      assert updated.last_talked_to != nil
    end

    test "delete_activity/1 removes the activity", %{
      contact: contact,
      account_id: account_id
    } do
      {:ok, activity} =
        Activities.create_activity(
          account_id,
          %{"title" => "Walk", "occurred_at" => "2026-03-15T10:00"},
          [contact.id],
          []
        )

      {:ok, _} = Activities.delete_activity(activity)
      assert Activities.list_activities_for_contact(contact.id) == []
    end
  end

  ## Life Events

  describe "life_events" do
    test "CRUD for life events", %{contact: contact, account_id: account_id} do
      [type | _] = Kith.Contacts.list_life_event_types(account_id)

      {:ok, le} =
        Activities.create_life_event(contact, %{
          "life_event_type_id" => type.id,
          "occurred_on" => "2026-01-15",
          "note" => "Got the job!"
        })

      assert le.note == "Got the job!"

      events = Activities.list_life_events(contact.id)
      assert length(events) == 1

      {:ok, updated} = Activities.update_life_event(le, %{"note" => "Updated note"})
      assert updated.note == "Updated note"

      {:ok, _} = Activities.delete_life_event(le)
      assert Activities.list_life_events(contact.id) == []
    end
  end

  ## Calls

  describe "calls" do
    test "create_call/2 with direction and updates last_talked_to", %{
      contact: contact,
      account_id: account_id
    } do
      [dir | _] = Kith.Contacts.list_call_directions()

      {:ok, call} =
        Activities.create_call(contact, %{
          "occurred_at" => "2026-03-15T14:00",
          "duration_mins" => "30",
          "call_direction_id" => dir.id,
          "notes" => "Caught up"
        })

      assert call.duration_mins == 30
      assert call.notes == "Caught up"

      # Verify last_talked_to updated
      updated_contact = Kith.Contacts.get_contact!(account_id, contact.id)
      assert updated_contact.last_talked_to != nil
    end

    test "CRUD for calls", %{contact: contact} do
      {:ok, call} =
        Activities.create_call(contact, %{
          "occurred_at" => "2026-03-15T10:00",
          "duration_mins" => "15"
        })

      calls = Activities.list_calls(contact.id)
      assert length(calls) == 1

      {:ok, updated} = Activities.update_call(call, %{"duration_mins" => "45"})
      assert updated.duration_mins == 45

      {:ok, _} = Activities.delete_call(call)
      assert Activities.list_calls(contact.id) == []
    end
  end
end
