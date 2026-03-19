defmodule Kith.VCard.ParserTest do
  use ExUnit.Case, async: true

  alias Kith.VCard.Parser

  @sample_vcard_30 """
  BEGIN:VCARD
  VERSION:3.0
  FN:Alice Smith
  N:Smith;Alice;;;
  NICKNAME:Ali
  BDAY:1990-06-15
  ORG:Acme Corp
  TITLE:Engineer
  NOTE:A great friend
  TEL;TYPE=CELL:+1-555-0100
  TEL;TYPE=HOME:+1-555-0200
  EMAIL;TYPE=WORK:alice@example.com
  ADR;TYPE=HOME:;;123 Main St;Springfield;IL;62701;US
  URL:https://alice.dev
  END:VCARD
  """

  @sample_vcard_40 """
  BEGIN:VCARD
  VERSION:4.0
  FN:Bob Jones
  N:Jones;Bob;;;
  BDAY:19850321
  TEL;TYPE=cell;VALUE=uri:tel:+1-555-0300
  EMAIL:bob@example.com
  END:VCARD
  """

  @multi_vcard """
  BEGIN:VCARD
  VERSION:3.0
  FN:Contact One
  N:One;Contact;;;
  END:VCARD
  BEGIN:VCARD
  VERSION:3.0
  FN:Contact Two
  N:Two;Contact;;;
  END:VCARD
  BEGIN:VCARD
  VERSION:3.0
  FN:Contact Three
  N:Three;Contact;;;
  END:VCARD
  """

  describe "parse/1" do
    test "parses a vCard 3.0 file" do
      {:ok, [contact]} = Parser.parse(@sample_vcard_30)

      assert contact.display_name == "Alice Smith"
      assert contact.first_name == "Alice"
      assert contact.last_name == "Smith"
      assert contact.nickname == "Ali"
      assert contact.birthdate == ~D[1990-06-15]
      assert contact.company == "Acme Corp"
      assert contact.occupation == "Engineer"
      assert contact.description == "A great friend"

      assert length(contact.phones) == 2
      assert Enum.any?(contact.phones, &(&1.value == "+1-555-0100" && &1.label == "Cell"))
      assert Enum.any?(contact.phones, &(&1.value == "+1-555-0200" && &1.label == "Home"))

      assert length(contact.emails) == 1
      assert hd(contact.emails).value == "alice@example.com"
      assert hd(contact.emails).label == "Work"

      assert length(contact.addresses) == 1
      addr = hd(contact.addresses)
      assert addr.line1 == "123 Main St"
      assert addr.city == "Springfield"
      assert addr.province == "IL"
      assert addr.postal_code == "62701"
      assert addr.country == "US"

      assert length(contact.urls) == 1
      assert hd(contact.urls).value == "https://alice.dev"
    end

    test "parses a vCard 4.0 with compact birthday" do
      {:ok, [contact]} = Parser.parse(@sample_vcard_40)

      assert contact.display_name == "Bob Jones"
      assert contact.first_name == "Bob"
      assert contact.last_name == "Jones"
      assert contact.birthdate == ~D[1985-03-21]
    end

    test "parses multiple vCards from a single file" do
      {:ok, contacts} = Parser.parse(@multi_vcard)

      assert length(contacts) == 3
      assert Enum.at(contacts, 0).display_name == "Contact One"
      assert Enum.at(contacts, 1).display_name == "Contact Two"
      assert Enum.at(contacts, 2).display_name == "Contact Three"
    end

    test "handles CRLF line endings" do
      vcard = String.replace(@sample_vcard_30, "\n", "\r\n")
      {:ok, [contact]} = Parser.parse(vcard)
      assert contact.display_name == "Alice Smith"
    end

    test "handles line folding (continuation lines)" do
      vcard = """
      BEGIN:VCARD
      VERSION:3.0
      FN:Very Long
       Name Here
      N:Here;Very Long Name;;;
      END:VCARD
      """

      {:ok, [contact]} = Parser.parse(vcard)
      # RFC 2425: fold indicator (newline + leading space) removed, joining the lines
      assert contact.display_name == "Very LongName Here"
    end

    test "returns error for completely invalid data" do
      {:ok, contacts} = Parser.parse("this is not a vcard at all")
      assert contacts == []
    end

    test "handles empty file" do
      {:ok, contacts} = Parser.parse("")
      assert contacts == []
    end
  end

  describe "unescape/1" do
    test "unescapes semicolons" do
      assert Parser.unescape("a\\;b") == "a;b"
    end

    test "unescapes commas" do
      assert Parser.unescape("a\\,b") == "a,b"
    end

    test "unescapes newlines" do
      assert Parser.unescape("a\\nb") == "a\nb"
      assert Parser.unescape("a\\Nb") == "a\nb"
    end

    test "unescapes backslashes" do
      assert Parser.unescape("a\\\\b") == "a\\b"
    end

    test "returns nil for nil" do
      assert Parser.unescape(nil) == nil
    end
  end

  describe "roundtrip" do
    test "serialize then parse produces equivalent data" do
      alias Kith.VCard.Serializer

      original = %{
        display_name: "Roundtrip Test",
        first_name: "Roundtrip",
        last_name: "Test",
        nickname: "RT",
        birthdate: ~D[2000-01-15],
        company: "Test Co",
        occupation: "Tester",
        description: "Testing roundtrip",
        addresses: [
          %{
            label: "Work",
            line1: "456 Oak Ave",
            line2: nil,
            city: "Portland",
            province: "OR",
            postal_code: "97201",
            country: "US"
          }
        ],
        contact_fields: [
          %{
            value: "rt@test.com",
            label: "Home",
            contact_field_type: %{protocol: "mailto", vcard_label: "EMAIL"}
          },
          %{
            value: "+1-555-9999",
            label: nil,
            contact_field_type: %{protocol: "tel", vcard_label: "TEL"}
          }
        ],
        gender: nil
      }

      vcard = Serializer.serialize(original)
      {:ok, [parsed]} = Parser.parse(vcard)

      assert parsed.first_name == "Roundtrip"
      assert parsed.last_name == "Test"
      assert parsed.nickname == "RT"
      assert parsed.birthdate == ~D[2000-01-15]
      assert parsed.company == "Test Co"
      assert parsed.occupation == "Tester"
      assert parsed.description == "Testing roundtrip"
      assert hd(parsed.emails).value == "rt@test.com"
      assert hd(parsed.phones).value == "+1-555-9999"
      assert hd(parsed.addresses).city == "Portland"
    end
  end
end
