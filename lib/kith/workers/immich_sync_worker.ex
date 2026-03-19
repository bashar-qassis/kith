defmodule Kith.Workers.ImmichSyncWorker do
  @moduledoc """
  Oban worker that syncs Immich people with Kith contacts for an account.

  For each active contact, performs exact case-insensitive name matching
  against Immich people. Creates immich_candidate records for matches.
  Never auto-confirms a link — the user always reviews.

  Implements circuit breaker: after 3 consecutive failures, sets
  `immich_status: :error` and stops retrying for that account.
  """

  use Oban.Worker, queue: :immich, max_attempts: 3

  import Ecto.Query
  require Logger

  alias Kith.Repo
  alias Kith.Accounts.Account
  alias Kith.Contacts.{Contact, ImmichCandidate}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    account = Repo.get!(Account, account_id)

    cond do
      account.immich_status == "error" ->
        Logger.info("Skipping Immich sync for account #{account_id}: circuit breaker open")
        :ok

      !account.immich_enabled ->
        Logger.debug("Skipping Immich sync for account #{account_id}: not enabled")
        :ok

      is_nil(account.immich_base_url) || is_nil(account.immich_api_key) ->
        Logger.debug("Skipping Immich sync for account #{account_id}: missing credentials")
        :ok

      true ->
        do_sync(account)
    end
  end

  defp do_sync(account) do
    case Kith.Immich.Client.list_people(account.immich_base_url, account.immich_api_key) do
      {:ok, people} ->
        process_matches(account, people)
        record_success(account)
        :ok

      {:error, reason} ->
        Logger.warning("Immich sync failed for account #{account.id}: #{inspect(reason)}")
        record_failure(account)
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Immich sync crashed for account #{account.id}: #{inspect(e)}")
      record_failure(account)
      {:error, :sync_crashed}
  end

  defp process_matches(account, people) do
    contacts =
      Contact
      |> where([c], c.account_id == ^account.id)
      |> where([c], is_nil(c.deleted_at))
      |> where([c], c.is_archived == false)
      |> Repo.all()

    people_by_name =
      people
      |> Enum.group_by(fn p -> String.downcase(p.name) end)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(contacts, fn contact ->
      if contact.immich_status == "linked" do
        # Never auto-unlink
        update_synced_at(contact, now)
      else
        full_name =
          [contact.first_name, contact.last_name]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join(" ")
          |> String.downcase()

        matches = Map.get(people_by_name, full_name, [])
        handle_matches(account, contact, matches, now)
      end
    end)
  end

  defp handle_matches(account, contact, [], now) do
    if contact.immich_status != "unlinked" do
      contact
      |> Contact.update_changeset(%{immich_status: "unlinked", immich_last_synced_at: now})
      |> Repo.update!()
    else
      update_synced_at(contact, now)
    end
  end

  defp handle_matches(account, contact, matches, now) do
    # Upsert candidates — don't duplicate existing ones
    Enum.each(matches, fn match ->
      attrs = %{
        account_id: account.id,
        contact_id: contact.id,
        immich_photo_id: match.id,
        immich_server_url: account.immich_base_url,
        thumbnail_url: match.thumbnail_url,
        suggested_at: now,
        status: "pending"
      }

      %ImmichCandidate{}
      |> ImmichCandidate.changeset(attrs)
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:contact_id, :immich_photo_id]
      )
    end)

    contact
    |> Contact.update_changeset(%{immich_status: "needs_review", immich_last_synced_at: now})
    |> Repo.update!()
  end

  defp update_synced_at(contact, now) do
    contact
    |> Contact.update_changeset(%{immich_last_synced_at: now})
    |> Repo.update!()
  end

  defp record_success(account) do
    account
    |> Account.immich_sync_changeset(%{
      immich_status: "ok",
      immich_consecutive_failures: 0,
      immich_last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update!()
  end

  defp record_failure(account) do
    new_count = account.immich_consecutive_failures + 1
    new_status = if new_count >= 3, do: "error", else: account.immich_status

    account
    |> Account.immich_sync_changeset(%{
      immich_status: new_status,
      immich_consecutive_failures: new_count
    })
    |> Repo.update!()
  end
end
