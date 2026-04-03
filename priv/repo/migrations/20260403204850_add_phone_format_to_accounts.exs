defmodule Kith.Repo.Migrations.AddPhoneFormatToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :phone_format, :string, default: "e164"
    end
  end
end
