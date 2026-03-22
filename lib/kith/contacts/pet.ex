defmodule Kith.Contacts.Pet do
  use Ecto.Schema
  import Ecto.Changeset

  @species ~w(dog cat bird fish reptile rabbit hamster other)

  schema "pets" do
    field :name, :string
    field :species, :string, default: "dog"
    field :breed, :string
    field :date_of_birth, :date
    field :date_of_death, :date
    field :notes, :string
    field :is_private, :boolean, default: true

    belongs_to :account, Kith.Accounts.Account
    belongs_to :contact, Kith.Contacts.Contact

    timestamps(type: :utc_datetime)
  end

  def changeset(pet, attrs) do
    pet
    |> cast(attrs, [
      :name,
      :species,
      :breed,
      :date_of_birth,
      :date_of_death,
      :notes,
      :is_private,
      :contact_id
    ])
    |> validate_required([:name])
    |> validate_inclusion(:species, @species)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:contact_id)
  end
end
