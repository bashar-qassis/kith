defmodule Kith.Workers.DuplicateDetectionWorker do
  @moduledoc """
  Oban worker that detects potential duplicate contacts within an account.
  Runs weekly via cron or can be triggered manually per-account.

  Detection algorithm:
  1. Name similarity via pg_trgm similarity() on display_name (threshold: 0.5)
  2. Exact email match across contact_fields
  3. Exact phone match across contact_fields
  4. Weighted score: name(0.4) + email(0.35) + phone(0.25)
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  import Ecto.Query
  alias Kith.Repo
  alias Kith.Contacts.{Contact, ContactField, DuplicateCandidate}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    detect_duplicates(account_id)
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    # Run for all accounts when triggered by cron (no account_id)
    account_ids =
      from(a in Kith.Accounts.Account, select: a.id)
      |> Repo.all()

    Enum.each(account_ids, &detect_duplicates/1)
    :ok
  end

  defp detect_duplicates(account_id) do
    # Get active contacts for this account
    contacts =
      Contact
      |> where([c], c.account_id == ^account_id)
      |> where([c], is_nil(c.deleted_at))
      |> select([c], %{id: c.id, display_name: c.display_name})
      |> Repo.all()

    if length(contacts) < 2, do: :ok, else: find_duplicates(account_id, contacts)
  end

  defp find_duplicates(account_id, _contacts) do
    # Find name-based duplicates using pg_trgm
    name_matches = find_name_matches(account_id)

    # Find email-based duplicates
    email_matches = find_email_matches(account_id)

    # Find phone-based duplicates
    phone_matches = find_phone_matches(account_id)

    # Merge and score all matches
    all_pairs =
      merge_matches(name_matches, email_matches, phone_matches)
      |> Enum.filter(fn {_pair, score, _reasons} -> score >= 0.4 end)

    # Get existing pending/dismissed candidates to avoid re-inserting
    existing =
      DuplicateCandidate
      |> where([d], d.account_id == ^account_id)
      |> where([d], d.status in ["pending", "dismissed"])
      |> select([d], {d.contact_id, d.duplicate_contact_id})
      |> Repo.all()
      |> MapSet.new()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Insert new candidates
    Enum.each(all_pairs, fn {{id1, id2}, score, reasons} ->
      # Canonicalize: smaller id first
      {contact_id, dup_id} = if id1 < id2, do: {id1, id2}, else: {id2, id1}

      unless MapSet.member?(existing, {contact_id, dup_id}) do
        %DuplicateCandidate{account_id: account_id}
        |> DuplicateCandidate.changeset(%{
          contact_id: contact_id,
          duplicate_contact_id: dup_id,
          score: score,
          reasons: reasons,
          detected_at: now
        })
        |> Repo.insert(on_conflict: :nothing)
      end
    end)
  end

  defp find_name_matches(account_id) do
    # Use pg_trgm similarity for fuzzy name matching
    query = """
    SELECT c1.id AS id1, c2.id AS id2, similarity(c1.display_name, c2.display_name) AS sim
    FROM contacts c1
    JOIN contacts c2 ON c1.id < c2.id
      AND c1.account_id = c2.account_id
    WHERE c1.account_id = $1
      AND c1.deleted_at IS NULL
      AND c2.deleted_at IS NULL
      AND similarity(c1.display_name, c2.display_name) > 0.5
    ORDER BY sim DESC
    LIMIT 500
    """

    case Repo.query(query, [account_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id1, id2, sim] ->
          {{id1, id2}, sim, ["name_match"]}
        end)

      _ ->
        []
    end
  end

  defp find_email_matches(account_id) do
    # Find contacts that share an exact email address
    query =
      from cf1 in ContactField,
        join: cf2 in ContactField,
        on: cf1.value == cf2.value and cf1.id < cf2.id,
        join: cft in assoc(cf1, :contact_field_type),
        where: cf1.account_id == ^account_id,
        where: cf2.account_id == ^account_id,
        where: cft.protocol == "mailto:",
        where: cf1.contact_id != cf2.contact_id,
        select: {cf1.contact_id, cf2.contact_id}

    query
    |> Repo.all()
    |> Enum.uniq()
    |> Enum.map(fn {id1, id2} ->
      {id1, id2} = if id1 < id2, do: {id1, id2}, else: {id2, id1}
      {{id1, id2}, 1.0, ["email_match"]}
    end)
    |> Enum.uniq_by(fn {pair, _, _} -> pair end)
  end

  defp find_phone_matches(account_id) do
    # Find contacts that share an exact phone number (normalized: digits only)
    query =
      from cf1 in ContactField,
        join: cf2 in ContactField,
        on:
          fragment("regexp_replace(?, '[^0-9]', '', 'g')", cf1.value) ==
            fragment("regexp_replace(?, '[^0-9]', '', 'g')", cf2.value) and cf1.id < cf2.id,
        join: cft in assoc(cf1, :contact_field_type),
        where: cf1.account_id == ^account_id,
        where: cf2.account_id == ^account_id,
        where: cft.protocol == "tel:",
        where: cf1.contact_id != cf2.contact_id,
        select: {cf1.contact_id, cf2.contact_id}

    query
    |> Repo.all()
    |> Enum.uniq()
    |> Enum.map(fn {id1, id2} ->
      {id1, id2} = if id1 < id2, do: {id1, id2}, else: {id2, id1}
      {{id1, id2}, 1.0, ["phone_match"]}
    end)
    |> Enum.uniq_by(fn {pair, _, _} -> pair end)
  end

  defp merge_matches(name_matches, email_matches, phone_matches) do
    # Group all matches by pair and compute weighted score
    all =
      (name_matches ++ email_matches ++ phone_matches)
      |> Enum.group_by(fn {pair, _score, _reasons} -> pair end)

    Enum.map(all, fn {pair, matches} ->
      reasons = matches |> Enum.flat_map(fn {_, _, r} -> r end) |> Enum.uniq()
      name_sim = Enum.find_value(matches, 0.0, fn {_, s, r} -> if "name_match" in r, do: s end)
      has_email = "email_match" in reasons
      has_phone = "phone_match" in reasons

      score =
        name_sim * 0.4 + if(has_email, do: 0.35, else: 0.0) + if(has_phone, do: 0.25, else: 0.0)

      score = min(score, 1.0)

      {pair, Float.round(score, 2), reasons}
    end)
  end
end
