defmodule Kith.DuplicateDetection do
  import Ecto.Query, warn: false
  import Kith.Scope
  alias Kith.Repo
  alias Kith.Contacts.DuplicateCandidate

  def list_candidates(account_id, opts \\ []) do
    status = Keyword.get(opts, :status, "pending")

    DuplicateCandidate
    |> scope_to_account(account_id)
    |> where([d], d.status == ^status)
    |> order_by([d], desc: d.score)
    |> Repo.all()
    |> Repo.preload([:contact, :duplicate_contact])
  end

  def get_candidate!(account_id, id) do
    DuplicateCandidate
    |> scope_to_account(account_id)
    |> Repo.get!(id)
    |> Repo.preload([:contact, :duplicate_contact])
  end

  def dismiss_candidate(%DuplicateCandidate{} = candidate) do
    candidate |> DuplicateCandidate.dismiss_changeset() |> Repo.update()
  end

  def mark_merged(%DuplicateCandidate{} = candidate) do
    candidate |> DuplicateCandidate.merge_changeset() |> Repo.update()
  end

  def pending_count(account_id) do
    DuplicateCandidate
    |> scope_to_account(account_id)
    |> where([d], d.status == "pending")
    |> Repo.aggregate(:count)
  end

  def pending_candidates_for_contact(account_id, contact_id) do
    from(dc in DuplicateCandidate,
      where: dc.account_id == ^account_id,
      where: dc.status == "pending",
      where: dc.contact_id == ^contact_id or dc.duplicate_contact_id == ^contact_id,
      order_by: [desc: :score],
      preload: [:contact, :duplicate_contact]
    )
    |> Repo.all()
  end

  def dismiss_candidates_for_contact(account_id, contact_id) do
    from(dc in DuplicateCandidate,
      where: dc.account_id == ^account_id,
      where: dc.status == "pending",
      where: dc.contact_id == ^contact_id or dc.duplicate_contact_id == ^contact_id
    )
    |> Repo.update_all(set: [status: "dismissed", resolved_at: DateTime.utc_now()])
  end
end
