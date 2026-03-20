defmodule KithWeb.API.NoteControllerTest do
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

  describe "POST /api/contacts/:contact_id/notes" do
    test "creates a note and returns 201", %{conn: conn, contact: contact} do
      conn =
        post(conn, ~p"/api/contacts/#{contact.id}/notes", %{
          "note" => %{"body" => "Hello world"}
        })

      assert %{"data" => %{"id" => id, "body" => "Hello world", "is_favorite" => false}} =
               json_response(conn, 201)

      assert is_integer(id)
    end
  end

  describe "GET /api/contacts/:contact_id/notes" do
    test "returns paginated list of notes", %{conn: conn, user: user, contact: contact} do
      {:ok, _} =
        Kith.Repo.insert(%Kith.Contacts.Note{
          contact_id: contact.id,
          account_id: user.account_id,
          body: "Note 1"
        })

      {:ok, _} =
        Kith.Repo.insert(%Kith.Contacts.Note{
          contact_id: contact.id,
          account_id: user.account_id,
          body: "Note 2"
        })

      conn = get(conn, ~p"/api/contacts/#{contact.id}/notes")
      assert %{"data" => notes, "meta" => meta} = json_response(conn, 200)
      assert length(notes) == 2
      assert is_map(meta)
    end
  end

  describe "GET /api/notes/:id" do
    test "returns a single note", %{conn: conn, user: user, contact: contact} do
      {:ok, note} =
        Kith.Repo.insert(%Kith.Contacts.Note{
          contact_id: contact.id,
          account_id: user.account_id,
          body: "Show me"
        })

      conn = get(conn, ~p"/api/notes/#{note.id}")
      assert %{"data" => %{"id" => _, "body" => "Show me"}} = json_response(conn, 200)
    end

    test "returns 404 for unknown note", %{conn: conn} do
      conn = get(conn, ~p"/api/notes/999999")
      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/notes/:id" do
    test "updates a note body", %{conn: conn, user: user, contact: contact} do
      {:ok, note} =
        Kith.Repo.insert(%Kith.Contacts.Note{
          contact_id: contact.id,
          account_id: user.account_id,
          body: "Original"
        })

      conn = patch(conn, ~p"/api/notes/#{note.id}", %{"note" => %{"body" => "Updated"}})
      assert %{"data" => %{"body" => "Updated"}} = json_response(conn, 200)
    end
  end

  describe "DELETE /api/notes/:id" do
    test "deletes a note and returns 204", %{conn: conn, user: user, contact: contact} do
      {:ok, note} =
        Kith.Repo.insert(%Kith.Contacts.Note{
          contact_id: contact.id,
          account_id: user.account_id,
          body: "Delete me"
        })

      conn = delete(conn, ~p"/api/notes/#{note.id}")
      assert conn.status == 204
    end
  end

  describe "POST /api/notes/:id/favorite" do
    test "marks note as favorite", %{conn: conn, user: user, contact: contact} do
      {:ok, note} =
        Kith.Repo.insert(%Kith.Contacts.Note{
          contact_id: contact.id,
          account_id: user.account_id,
          body: "Fav me"
        })

      conn = post(conn, ~p"/api/notes/#{note.id}/favorite")
      assert %{"data" => %{"is_favorite" => true}} = json_response(conn, 200)
    end
  end

  describe "DELETE /api/notes/:id/favorite" do
    test "removes favorite from note", %{conn: conn, user: user, contact: contact} do
      {:ok, note} =
        Kith.Repo.insert(%Kith.Contacts.Note{
          contact_id: contact.id,
          account_id: user.account_id,
          body: "Unfav me",
          is_favorite: true
        })

      conn = delete(conn, ~p"/api/notes/#{note.id}/favorite")
      assert %{"data" => %{"is_favorite" => false}} = json_response(conn, 200)
    end
  end
end
