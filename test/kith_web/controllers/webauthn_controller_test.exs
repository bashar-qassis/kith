defmodule KithWeb.WebauthnControllerTest do
  use KithWeb.ConnCase

  alias Kith.Accounts.WebauthnCredential
  import Kith.AccountsFixtures

  @fake_cose_key %{
    1 => 2,
    3 => -7,
    -1 => 1,
    -2 => :crypto.strong_rand_bytes(32),
    -3 => :crypto.strong_rand_bytes(32)
  }

  defp create_credential(user, opts \\ []) do
    %WebauthnCredential{}
    |> WebauthnCredential.changeset(%{
      user_id: user.id,
      credential_id: Keyword.get(opts, :credential_id, :crypto.strong_rand_bytes(32)),
      public_key: :erlang.term_to_binary(@fake_cose_key),
      sign_count: 0,
      name: Keyword.get(opts, :name, "Test Key")
    })
    |> Kith.Repo.insert!()
  end

  describe "register_challenge (POST /auth/webauthn/register/challenge)" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "returns publicKey options with challenge", %{conn: conn, user: user} do
      conn = post(conn, ~p"/auth/webauthn/register/challenge")
      assert %{"publicKey" => public_key} = json_response(conn, 200)

      assert public_key["challenge"]
      assert public_key["rp"]["name"] == "Kith"
      assert public_key["user"]["name"] == user.email
      assert is_list(public_key["pubKeyCredParams"])
      assert is_list(public_key["excludeCredentials"])
    end

    test "excludes existing credentials", %{conn: conn, user: user} do
      cred = create_credential(user)

      conn = post(conn, ~p"/auth/webauthn/register/challenge")
      %{"publicKey" => public_key} = json_response(conn, 200)

      excluded_ids = Enum.map(public_key["excludeCredentials"], & &1["id"])
      expected_id = Base.url_encode64(cred.credential_id, padding: false)
      assert expected_id in excluded_ids
    end
  end

  describe "register_complete (POST /auth/webauthn/register/complete)" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "returns 400 without pending challenge", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/webauthn/register/complete", %{
          "attestationObject" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false),
          "name" => "My Key"
        })

      assert json_response(conn, 400)["error"] =~ "No pending challenge"
    end
  end

  describe "authenticate_challenge (POST /auth/webauthn/authenticate/challenge)" do
    test "returns challenge without email", %{conn: conn} do
      conn = post(conn, ~p"/auth/webauthn/authenticate/challenge")
      assert %{"publicKey" => public_key} = json_response(conn, 200)
      assert public_key["challenge"]
      assert public_key["allowCredentials"] == []
    end

    test "returns challenge with allow_credentials when email has WebAuthn", %{conn: conn} do
      user = user_fixture()
      cred = create_credential(user)

      conn = post(conn, ~p"/auth/webauthn/authenticate/challenge", %{"email" => user.email})
      assert %{"publicKey" => public_key} = json_response(conn, 200)
      assert public_key["challenge"]

      allowed_ids = Enum.map(public_key["allowCredentials"], & &1["id"])
      expected_id = Base.url_encode64(cred.credential_id, padding: false)
      assert expected_id in allowed_ids
    end

    test "returns empty allow_credentials for unknown email", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/webauthn/authenticate/challenge", %{
          "email" => "nobody@example.com"
        })

      assert %{"publicKey" => public_key} = json_response(conn, 200)
      assert public_key["allowCredentials"] == []
    end
  end

  describe "authenticate_complete (POST /auth/webauthn/authenticate/complete)" do
    test "returns 400 without pending challenge", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/webauthn/authenticate/complete", %{
          "credentialId" => Base.url_encode64("fake", padding: false),
          "authenticatorData" => Base.url_encode64("fake", padding: false),
          "signature" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false)
        })

      assert json_response(conn, 400)["error"] =~ "No pending challenge"
    end
  end

  describe "list_credentials (GET /auth/webauthn/credentials)" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "returns user's credentials", %{conn: conn, user: user} do
      create_credential(user, name: "My Yubikey")
      create_credential(user, name: "Touch ID")

      conn = get(conn, ~p"/auth/webauthn/credentials")
      assert %{"credentials" => creds} = json_response(conn, 200)
      assert length(creds) == 2
      names = Enum.map(creds, & &1["name"])
      assert "My Yubikey" in names
      assert "Touch ID" in names
    end

    test "returns empty list when no credentials", %{conn: conn} do
      conn = get(conn, ~p"/auth/webauthn/credentials")
      assert %{"credentials" => []} = json_response(conn, 200)
    end
  end

  describe "delete_credential (DELETE /auth/webauthn/credentials/:id)" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "deletes a credential", %{conn: conn, user: user} do
      cred = create_credential(user)
      conn = delete(conn, ~p"/auth/webauthn/credentials/#{cred.id}")
      assert json_response(conn, 200)["status"] == "ok"
    end

    test "returns 404 for non-existent credential", %{conn: conn} do
      conn = delete(conn, ~p"/auth/webauthn/credentials/999999")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end
end
