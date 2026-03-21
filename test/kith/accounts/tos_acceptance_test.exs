defmodule Kith.Accounts.TosAcceptanceTest do
  use Kith.DataCase, async: true

  alias Kith.Accounts.User

  describe "registration_changeset with ToS required" do
    setup do
      original = Application.get_env(:kith, :require_tos_acceptance, false)
      Application.put_env(:kith, :require_tos_acceptance, true)
      on_exit(fn -> Application.put_env(:kith, :require_tos_acceptance, original) end)
      :ok
    end

    test "valid when tos_accepted is true" do
      changeset =
        User.registration_changeset(%User{}, %{
          email: "test@example.com",
          password: "valid_password123",
          tos_accepted: true
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tos_accepted_at)
    end

    test "invalid when tos_accepted is false" do
      changeset =
        User.registration_changeset(%User{}, %{
          email: "test@example.com",
          password: "valid_password123",
          tos_accepted: false
        })

      refute changeset.valid?
      assert {"you must accept the Terms of Service", _} = changeset.errors[:tos_accepted]
    end

    test "invalid when tos_accepted is missing" do
      changeset =
        User.registration_changeset(%User{}, %{
          email: "test@example.com",
          password: "valid_password123"
        })

      refute changeset.valid?
      assert {"you must accept the Terms of Service", _} = changeset.errors[:tos_accepted]
    end
  end

  describe "registration_changeset without ToS required" do
    setup do
      original = Application.get_env(:kith, :require_tos_acceptance, false)
      Application.put_env(:kith, :require_tos_acceptance, false)
      on_exit(fn -> Application.put_env(:kith, :require_tos_acceptance, original) end)
      :ok
    end

    test "valid without tos_accepted" do
      changeset =
        User.registration_changeset(%User{}, %{
          email: "test@example.com",
          password: "valid_password123"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :tos_accepted_at)
    end
  end
end
