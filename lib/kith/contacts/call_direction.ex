defmodule Kith.Contacts.CallDirection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "call_directions" do
    field :name, :string
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(call_direction, attrs) do
    call_direction
    |> cast(attrs, [:name, :position])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
