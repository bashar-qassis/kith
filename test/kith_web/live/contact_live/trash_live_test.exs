defmodule KithWeb.ContactLive.TrashLiveTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kith.ContactsFixtures
  import Kith.AccountsFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    seed_reference_data!()
    %{account_id: user.account_id}
  end

  defp trashed_contact(account_id) do
    contact = contact_fixture(account_id)
    {:ok, trashed} = Kith.Contacts.soft_delete_contact(contact)
    trashed
  end

  describe "trash page rendering" do
    @tag :integration
    test "renders with trashed contacts", %{conn: conn, account_id: account_id} do
      contact = trashed_contact(account_id)
      {:ok, _view, html} = live(conn, ~p"/contacts/trash")
      assert html =~ contact.display_name
    end

    @tag :integration
    test "shows empty state when no contacts are trashed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contacts/trash")
      assert html =~ "Trash is empty"
    end

    @tag :integration
    test "Empty Trash button is visible when contacts exist", %{
      conn: conn,
      account_id: account_id
    } do
      trashed_contact(account_id)
      {:ok, _view, html} = live(conn, ~p"/contacts/trash")
      assert html =~ "Empty Trash"
    end

    @tag :integration
    test "Empty Trash button is hidden when trash is empty", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contacts/trash")
      assert html =~ "Trash is empty"
      # The modal trigger button should not be rendered when trash is empty
      refute html =~ "empty-trash-modal"
    end
  end

  describe "empty-trash event" do
    @tag :integration
    test "clears all trashed contacts and shows flash", %{
      conn: conn,
      account_id: account_id
    } do
      trashed_contact(account_id)
      trashed_contact(account_id)

      {:ok, view, _html} = live(conn, ~p"/contacts/trash")

      html = render_click(view, "empty-trash")

      assert html =~ "permanently deleted"
      assert html =~ "Trash is empty"
    end

    @tag :integration
    test "shows singular flash message when only one contact is deleted", %{
      conn: conn,
      account_id: account_id
    } do
      trashed_contact(account_id)

      {:ok, view, _html} = live(conn, ~p"/contacts/trash")

      html = render_click(view, "empty-trash")

      assert html =~ "1 contact permanently deleted"
    end

    @tag :integration
    test "unauthorized user (viewer) cannot empty trash", %{conn: conn} do
      viewer = user_fixture(%{role: "viewer"})
      viewer_conn = log_in_user(conn, viewer)

      {:ok, view, _html} = live(viewer_conn, ~p"/contacts/trash")

      html = render_click(view, "empty-trash")
      assert html =~ "not authorized"
    end
  end
end
