defmodule KithWeb.ContactLive.ShowTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Kith.ContactsFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    seed_reference_data!()
    contact = contact_fixture(user.account_id)
    %{contact: contact, account_id: user.account_id}
  end

  describe "contact profile page" do
    test "renders contact name and sidebar", %{conn: conn, contact: contact} do
      {:ok, _view, html} = live(conn, ~p"/contacts/#{contact.id}")
      assert html =~ contact.display_name
      assert html =~ "Notes"
    end

    test "tab switching works", %{conn: conn, contact: contact} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # The contact show page has 3 tabs: Notes (default), Life Events, Photos
      # Addresses, Contact Info, and Relationships are sidebar cards (always visible)
      html = view |> element("button", "Life Events") |> render_click()
      assert html =~ "Life Events"

      html = view |> element("button", "Photos") |> render_click()
      assert html =~ "Photos"

      html = view |> element("button", "Notes") |> render_click()
      assert html =~ "Notes"
    end

    test "shows empty state messages", %{conn: conn, contact: contact} do
      {:ok, _view, html} = live(conn, ~p"/contacts/#{contact.id}")
      assert html =~ "No notes yet"
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
    test "create a note via context and verify it renders", %{
      conn: conn,
      contact: contact,
      user: user
    } do
      # Create note directly via context (Trix hidden input can't be set via LiveViewTest)
      note_fixture(contact, user.id, %{"body" => "<p>Test note content</p>"})

      {:ok, _view, html} = live(conn, ~p"/contacts/#{contact.id}")
      assert html =~ "Test note content"
    end

    test "shows Add Note button", %{conn: conn, contact: contact} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # Click the header "Add Note" button
      html = view |> element("#add-note-#{contact.id}") |> render_click()
      assert html =~ "trix-editor"
      assert html =~ "Private"
    end
  end

  describe "addresses section" do
    test "add an address", %{conn: conn, contact: contact} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # Addresses section is always visible in the sidebar — target header button
      view |> element("#add-address-#{contact.id}") |> render_click()

      # Submit via render_submit with the component target
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

      # Verify the address was created in the database
      addresses = Kith.Contacts.list_addresses(contact.id)
      assert length(addresses) == 1
      assert hd(addresses).line1 == "456 Oak Ave"

      # Re-render to see the address displayed
      html = render(view)
      assert html =~ "456 Oak Ave"
    end
  end

  describe "contact fields section" do
    test "add a contact field", %{conn: conn, contact: contact, account_id: account_id} do
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # Contact Info section is always visible in the sidebar
      [email_type | _] = Kith.Contacts.list_contact_field_types(account_id)

      view |> element("button", "Add Info") |> render_click()

      view
      |> form("form[phx-submit=save]", %{
        contact_field: %{value: "jane@example.com", contact_field_type_id: email_type.id}
      })
      |> render_submit()

      # Verify in database
      fields = Kith.Contacts.list_contact_fields(contact.id)
      assert length(fields) == 1
      assert hd(fields).value == "jane@example.com"

      html = render(view)
      assert html =~ "jane@example.com"
    end
  end
end
