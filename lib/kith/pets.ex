defmodule Kith.Pets do
  import Ecto.Query, warn: false
  import Kith.Scope

  alias Kith.Contacts.Pet
  alias Kith.Repo

  def list_pets(account_id, contact_id) do
    Pet
    |> scope_to_account(account_id)
    |> where([p], p.contact_id == ^contact_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  def get_pet!(account_id, id) do
    Pet |> scope_to_account(account_id) |> Repo.get!(id)
  end

  def create_pet(account_id, attrs) do
    %Pet{account_id: account_id}
    |> Pet.changeset(attrs)
    |> Repo.insert()
  end

  def update_pet(%Pet{} = pet, attrs) do
    pet |> Pet.changeset(attrs) |> Repo.update()
  end

  def delete_pet(%Pet{} = pet), do: Repo.delete(pet)
end
