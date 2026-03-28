defmodule KithWeb.DAV.TestHelpers do
  @moduledoc """
  Shared helpers for CardDAV black-box integration tests.

  Provides HTTP Basic Auth, custom DAV method dispatch, vCard builders,
  and XML body templates used across all DAV test files.
  """

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint KithWeb.Endpoint
  @password "hello world!!"

  def dav_password, do: @password

  def basic_auth(conn, email, password) do
    encoded = Base.encode64("#{email}:#{password}")
    put_req_header(conn, "authorization", "Basic #{encoded}")
  end

  def dav_request(conn, method, path, body \\ "") do
    content_type =
      case method do
        "PUT" -> "text/vcard"
        _ -> "application/xml"
      end

    conn
    |> put_req_header("content-type", content_type)
    |> dispatch(@endpoint, method, path, body)
  end

  def authed_dav(%{conn: conn, user: user}, method, path, body \\ "") do
    conn
    |> basic_auth(user.email, @password)
    |> dav_request(method, path, body)
  end

  def build_vcard(first_name, last_name, opts \\ []) do
    lines = [
      "BEGIN:VCARD",
      "VERSION:3.0",
      "FN:#{first_name} #{last_name}",
      "N:#{last_name};#{first_name};;;"
    ]

    lines = if opts[:uid], do: lines ++ ["UID:#{opts[:uid]}"], else: lines
    lines = if opts[:nickname], do: lines ++ ["NICKNAME:#{opts[:nickname]}"], else: lines
    lines = if opts[:company], do: lines ++ ["ORG:#{opts[:company]}"], else: lines
    lines = if opts[:occupation], do: lines ++ ["TITLE:#{opts[:occupation]}"], else: lines
    lines = if opts[:birthdate], do: lines ++ ["BDAY:#{opts[:birthdate]}"], else: lines
    lines = if opts[:email], do: lines ++ ["EMAIL;TYPE=HOME:#{opts[:email]}"], else: lines
    lines = if opts[:phone], do: lines ++ ["TEL;TYPE=CELL:#{opts[:phone]}"], else: lines
    lines = if opts[:note], do: lines ++ ["NOTE:#{opts[:note]}"], else: lines

    lines = lines ++ ["END:VCARD"]
    Enum.join(lines, "\r\n") <> "\r\n"
  end

  def contact_uid(contact), do: "kith-contact-#{contact.id}.vcf"

  def contact_path(contact),
    do: "/dav/addressbooks/default/#{contact_uid(contact)}"

  def propfind_body do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:cs="http://calendarserver.org/ns/">
      <d:allprop/>
    </d:propfind>
    """
  end

  def multiget_body(hrefs) do
    href_xml = Enum.map_join(hrefs, "\n", fn href -> "<d:href>#{href}</d:href>" end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <card:addressbook-multiget xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:prop>
        <d:getetag/>
        <card:address-data/>
      </d:prop>
      #{href_xml}
    </card:addressbook-multiget>
    """
  end

  def sync_collection_body do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <d:sync-collection xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:sync-token/>
      <d:prop>
        <d:getetag/>
        <card:address-data/>
      </d:prop>
    </d:sync-collection>
    """
  end

  def count_responses(body) do
    Regex.scan(~r/<d:response>/, body) |> length()
  end

  @doc "Standard setup block: creates a user and returns context with conn, user, scope, account_id."
  def setup_dav_user(%{conn: conn}) do
    user = Kith.AccountsFixtures.user_fixture()
    scope = Kith.Accounts.Scope.for_user(user)

    # Ensure global ContactFieldTypes exist for DAV contact field round-trips
    ensure_contact_field_types()

    %{
      conn: conn,
      user: user,
      scope: scope,
      account_id: user.account.id
    }
  end

  defp ensure_contact_field_types do
    alias Kith.Contacts.ContactFieldType
    alias Kith.Repo
    import Ecto.Query

    # Seeds store protocols with colons ("mailto:", "tel:", "https://").
    # Only insert if no types exist for each protocol scheme.
    for {name, protocol, seeded} <- [
          {"Email", "mailto", "mailto:"},
          {"Phone", "tel", "tel:"},
          {"Website", "https", "https://"}
        ] do
      unless Repo.one(
               from(t in ContactFieldType,
                 where: like(t.protocol, ^"#{protocol}%"),
                 limit: 1
               )
             ) do
        Repo.insert!(%ContactFieldType{name: name, protocol: seeded, position: 0})
      end
    end
  end
end
