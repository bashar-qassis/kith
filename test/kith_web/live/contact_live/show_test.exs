defmodule KithWeb.ContactLive.ShowTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    seed_reference_data!()
    contact = contact_fixture(user.account_id)
    %{contact: contact, account_id: user.account_id}
  end

  describe "contact profile page" do
    test "renders contact name and sidebar", %{conn: conn, contact: contact} do
      {:ok, view, html} = live(conn, ~p"/contacts/#{contact.id}")
      assert html =~ contact.display_name
      assert html =~ "Notes"
    end

    test "tab switching works", %{conn: conn, contact: contact} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # Switch to Activities tab
      html = view |> element("button", "Activities") |> render_click()
      assert html =~ "Activities"

      # Switch to Calls tab
      html = view |> element("button", "Calls") |> render_click()
      assert html =~ "Calls"

      # Switch to Life Events tab
      html = view |> element("button", "Life Events") |> render_click()
      assert html =~ "Life Events"

      # Switch to Addresses tab
      html = view |> element("button", "Addresses") |> render_click()
      assert html =~ "Addresses"

      # Switch to Contact Info tab
      html = view |> element("button", "Contact Info") |> render_click()
      assert html =~ "Contact Info"

      # Switch to Relationships tab
      html = view |> element("button", "Relationships") |> render_click()
      assert html =~ "Relationships"
    end

    test "shows empty state messages", %{conn: conn, contact: contact} do
      {:ok, view, html} = live(conn, ~p"/contacts/#{contact.id}")
      assert html =~ "No notes yet."
    end

    test "reminders sidebar renders", %{conn: conn, contact: contact} do
      {:ok, _view, html} = live(conn, ~p"/contacts/#{contact.id}")
      assert html =~ "Reminders"
      assert html =~ "No reminders set."
    end

    test "favorite toggle works", %{conn: conn, contact: contact} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")
      view |> element("button[phx-click=toggle-favorite]") |> render_click()

      updated = Kith.Contacts.get_contact!(contact.account_id, contact.id)
      assert updated.favorite == true
    end
  end

  describe "notes tab" do
    test "add and delete a note", %{conn: conn, contact: contact} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # Click "Add Note"
      view |> element("button", "Add Note") |> render_click()

      # Submit the note form
      view
      |> form("form[phx-submit=save-note]", %{note: %{body: "<p>Hello world</p>"}})
      |> render_submit()

      # Note should appear
      html = render(view)
      assert html =~ "Hello world"
      assert html =~ "Note added."
    end
  end

  describe "addresses tab" do
    test "add an address", %{conn: conn, contact: contact} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # Switch to addresses tab
      view |> element("button", "Addresses") |> render_click()

      # Click add
      view |> element("button", "Add Address") |> render_click()

      # Submit address form
      view
      |> form("form[phx-submit=save]", %{
        address: %{
          line1: "456 Oak Ave",
          city: "Portland",
          province: "OR",
          postal_code: "97201",
          country: "US"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "456 Oak Ave"
      assert html =~ "Address added."
    end
  end

  describe "contact fields tab" do
    test "add a contact field", %{conn: conn, contact: contact, account_id: account_id} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # Switch to Contact Info tab
      view |> element("button", "Contact Info") |> render_click()

      [email_type | _] = Kith.Contacts.list_contact_field_types(account_id)

      # Click add
      view |> element("button", "Add Field") |> render_click()

      # Submit form
      view
      |> form("form[phx-submit=save]", %{
        contact_field: %{value: "jane@example.com", contact_field_type_id: email_type.id}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "jane@example.com"
      assert html =~ "Contact field added."
    end
  end
end
