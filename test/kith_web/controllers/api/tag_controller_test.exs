defmodule KithWeb.API.TagControllerTest do
  use KithWeb.ConnCase

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  defp authed_conn(conn, user) do
    {raw_token, _} = Kith.Accounts.generate_api_token(user)
    put_req_header(conn, "authorization", "Bearer #{raw_token}")
  end

  setup %{conn: conn} do
    user = user_fixture()
    contact = contact_fixture(user.account_id, %{})
    conn = authed_conn(conn, user)
    %{conn: conn, user: user, contact: contact}
  end

  describe "POST /api/tags" do
    test "creates a tag and returns 201", %{conn: conn} do
      conn = post(conn, ~p"/api/tags", %{"tag" => %{"name" => "Family"}})
      assert %{"data" => %{"id" => id, "name" => "Family"}} = json_response(conn, 201)
      assert is_integer(id)
    end

    test "duplicate tag name returns 409", %{conn: conn, user: user} do
      post(conn, ~p"/api/tags", %{"tag" => %{"name" => "Duplicate"}})

      conn2 =
        build_conn()
        |> authed_conn(user)
        |> post(~p"/api/tags", %{"tag" => %{"name" => "Duplicate"}})

      assert %{"status" => 409} = json_response(conn2, 409)
    end
  end

  describe "GET /api/tags" do
    test "lists all tags for the account", %{conn: conn, user: user} do
      {:ok, _} = Kith.Contacts.create_tag(user.account_id, %{"name" => "Friends"})
      {:ok, _} = Kith.Contacts.create_tag(user.account_id, %{"name" => "Work"})

      conn = get(conn, ~p"/api/tags")
      assert %{"data" => tags} = json_response(conn, 200)
      names = Enum.map(tags, & &1["name"])
      assert "Friends" in names
      assert "Work" in names
    end
  end

  describe "PATCH /api/tags/:id" do
    test "updates a tag name", %{conn: conn, user: user} do
      {:ok, tag} = Kith.Contacts.create_tag(user.account_id, %{"name" => "Old"})

      conn = patch(conn, ~p"/api/tags/#{tag.id}", %{"tag" => %{"name" => "New"}})
      assert %{"data" => %{"name" => "New"}} = json_response(conn, 200)
    end
  end

  describe "DELETE /api/tags/:id" do
    test "deletes a tag and returns 204", %{conn: conn, user: user} do
      {:ok, tag} = Kith.Contacts.create_tag(user.account_id, %{"name" => "ToDelete"})

      conn = delete(conn, ~p"/api/tags/#{tag.id}")
      assert conn.status == 204
    end
  end

  describe "POST /api/contacts/:contact_id/tags (assign)" do
    test "assigns a tag to a contact", %{conn: conn, user: user, contact: contact} do
      {:ok, tag} = Kith.Contacts.create_tag(user.account_id, %{"name" => "VIP"})

      conn = post(conn, ~p"/api/contacts/#{contact.id}/tags", %{"tag_id" => tag.id})
      assert %{"data" => %{"status" => "assigned"}} = json_response(conn, 200)
    end
  end

  describe "GET /api/contacts/:id?include=tags" do
    test "returns contact with tags array", %{conn: conn, user: user, contact: contact} do
      {:ok, tag} = Kith.Contacts.create_tag(user.account_id, %{"name" => "Included"})
      Kith.Contacts.tag_contact(contact, tag)

      conn = get(conn, ~p"/api/contacts/#{contact.id}?include=tags")
      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data["tags"])
      assert Enum.any?(data["tags"], fn t -> t["name"] == "Included" end)
    end
  end

  describe "DELETE /api/contacts/:contact_id/tags/:tag_id (remove)" do
    test "removes a tag from a contact", %{conn: conn, user: user, contact: contact} do
      {:ok, tag} = Kith.Contacts.create_tag(user.account_id, %{"name" => "Removable"})
      Kith.Contacts.tag_contact(contact, tag)

      conn = delete(conn, ~p"/api/contacts/#{contact.id}/tags/#{tag.id}")
      assert conn.status == 204
    end
  end
end
