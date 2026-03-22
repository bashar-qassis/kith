defmodule KithWeb.API.ContactControllerFirstMetTest do
  use KithWeb.ConnCase, async: true

  alias Kith.Contacts
  alias KithWeb.API.ContactJSON

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    {raw_token, _} = Kith.Accounts.generate_api_token(user)
    conn = put_req_header(conn, "authorization", "Bearer #{raw_token}")
    %{conn: conn, user: user, account_id: user.account_id}
  end

  describe "ContactJSON.data/1 serializes first-met fields" do
    test "includes all new fields", %{account_id: account_id} do
      met_through = contact_fixture(account_id, %{first_name: "Sarah"})

      {:ok, contact} =
        Contacts.create_contact(account_id, %{
          first_name: "Jane",
          middle_name: "Marie",
          last_name: "Doe",
          first_met_at: ~D[2020-06-15],
          first_met_year_unknown: false,
          first_met_where: "College",
          first_met_through_id: met_through.id,
          first_met_additional_info: "Orientation week",
          birthdate_year_unknown: false
        })

      json = ContactJSON.data(contact)
      assert json.middle_name == "Marie"
      assert json.first_met_at == ~D[2020-06-15]
      assert json.first_met_year_unknown == false
      assert json.first_met_where == "College"
      assert json.first_met_additional_info == "Orientation week"
      assert json.birthdate_year_unknown == false
    end

    test "formats date without year when year_unknown is true", %{account_id: account_id} do
      {:ok, contact} =
        Contacts.create_contact(account_id, %{
          first_name: "Jane",
          first_met_at: ~D[0001-06-15],
          first_met_year_unknown: true,
          birthdate: ~D[0001-03-20],
          birthdate_year_unknown: true
        })

      json = ContactJSON.data(contact)
      assert json.first_met_at == "--06-15"
      assert json.birthdate == "--03-20"
    end

    test "formats date normally when year_unknown is false", %{account_id: account_id} do
      {:ok, contact} =
        Contacts.create_contact(account_id, %{
          first_name: "Jane",
          first_met_at: ~D[2020-06-15],
          first_met_year_unknown: false,
          birthdate: ~D[1990-03-20],
          birthdate_year_unknown: false
        })

      json = ContactJSON.data(contact)
      assert json.first_met_at == ~D[2020-06-15]
      assert json.birthdate == ~D[1990-03-20]
    end
  end

  describe "GET /api/contacts/:id includes first_met_through" do
    test "serializes first_met_through association on show", %{conn: conn, account_id: account_id} do
      met_through = contact_fixture(account_id, %{first_name: "Sarah", last_name: "Ahmed"})

      {:ok, contact} =
        Contacts.create_contact(account_id, %{
          first_name: "Jane",
          first_met_through_id: met_through.id
        })

      conn = get(conn, ~p"/api/contacts/#{contact.id}?include=first_met_through")
      json = json_response(conn, 200)["data"]
      assert json["first_met_through"]["id"] == met_through.id
      assert json["first_met_through"]["display_name"] == "Sarah Ahmed"
    end

    test "serializes null when first_met_through is not set", %{
      conn: conn,
      account_id: account_id
    } do
      {:ok, contact} = Contacts.create_contact(account_id, %{first_name: "Jane"})

      conn = get(conn, ~p"/api/contacts/#{contact.id}?include=first_met_through")
      json = json_response(conn, 200)["data"]
      assert json["first_met_through"] == nil
    end
  end
end
