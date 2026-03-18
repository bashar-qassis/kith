defmodule Kith.Contacts.Currency do
  use Ecto.Schema
  import Ecto.Changeset

  schema "currencies" do
    field :code, :string
    field :name, :string
    field :symbol, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(currency, attrs) do
    currency
    |> cast(attrs, [:code, :name, :symbol])
    |> validate_required([:code, :name, :symbol])
    |> unique_constraint(:code)
  end
end
