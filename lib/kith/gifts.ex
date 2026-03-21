defmodule Kith.Gifts do
  import Ecto.Query, warn: false
  import Kith.Scope
  alias Kith.Repo
  alias Kith.Contacts.Gift

  def list_gifts(account_id, contact_id) do
    Gift
    |> scope_to_account(account_id)
    |> where([g], g.contact_id == ^contact_id)
    |> order_by([g], desc: g.inserted_at)
    |> Repo.all()
  end

  def get_gift!(account_id, id) do
    Gift |> scope_to_account(account_id) |> Repo.get!(id)
  end

  def create_gift(account_id, creator_id, attrs) do
    %Gift{account_id: account_id, creator_id: creator_id}
    |> Gift.changeset(attrs)
    |> Repo.insert()
  end

  def update_gift(%Gift{} = gift, attrs) do
    gift |> Gift.changeset(attrs) |> Repo.update()
  end

  def delete_gift(%Gift{} = gift), do: Repo.delete(gift)

  def list_gift_ideas(account_id) do
    Gift
    |> scope_to_account(account_id)
    |> where([g], g.status == "idea")
    |> order_by([g], asc: g.date)
    |> Repo.all()
  end
end
