defmodule Kith.VCard.SerializerTest do
  use ExUnit.Case, async: true

  alias Kith.VCard.Serializer

  describe "serialize/1" do
    test "generates valid vCard 3.0 with all fields" do
      contact = %{
        display_name: "Alice Smith",
        first_name: "Alice",
        last_name: "Smith",
        nickname: "Ali",
        birthdate: ~D[1990-06-15],
        company: "Acme Corp",
        occupation: "Engineer",
        description: "A great friend",
        addresses: [
          %{
            label: "Home",
            line1: "123 Main St",
            line2: "Apt 4",
            city: "Springfield",
            province: "IL",
            postal_code: "62701",
            country: "US"
          }
        ],
        contact_fields: [
          %{
            value: "alice@example.com",
            label: "Work",
            contact_field_type: %{protocol: "mailto", vcard_label: "EMAIL"}
          },
          %{
            value: "+1-555-0100",
            label: "Cell",
            contact_field_type: %{protocol: "tel", vcard_label: "TEL"}
          },
          %{
            value: "https://alice.dev",
            label: nil,
            contact_field_type: %{protocol: "https", vcard_label: nil}
          }
        ],
        gender: nil
      }

      vcard = Serializer.serialize(contact)

      assert String.contains?(vcard, "BEGIN:VCARD\r\n")
      assert String.contains?(vcard, "VERSION:3.0\r\n")
      assert String.contains?(vcard, "FN:Alice Smith\r\n")
      assert String.contains?(vcard, "N:Smith;Alice;;;\r\n")
      assert String.contains?(vcard, "NICKNAME:Ali\r\n")
      assert String.contains?(vcard, "BDAY:1990-06-15\r\n")
      assert String.contains?(vcard, "ORG:Acme Corp\r\n")
      assert String.contains?(vcard, "TITLE:Engineer\r\n")
      assert String.contains?(vcard, "NOTE:A great friend\r\n")
      assert String.contains?(vcard, "EMAIL;TYPE=WORK:alice@example.com\r\n")
      assert String.contains?(vcard, "TEL;TYPE=CELL:+1-555-0100\r\n")
      assert String.contains?(vcard, "URL:https://alice.dev\r\n")

      assert String.contains?(
               vcard,
               "ADR;TYPE=HOME:;Apt 4;123 Main St;Springfield;IL;62701;US\r\n"
             )

      assert String.contains?(vcard, "END:VCARD\r\n")
    end

    test "omits nil fields" do
      contact = %{
        display_name: "Bob",
        first_name: "Bob",
        last_name: nil,
        nickname: nil,
        birthdate: nil,
        company: nil,
        occupation: nil,
        description: nil,
        addresses: [],
        contact_fields: [],
        gender: nil
      }

      vcard = Serializer.serialize(contact)

      assert String.contains?(vcard, "FN:Bob")
      refute String.contains?(vcard, "NICKNAME")
      refute String.contains?(vcard, "BDAY")
      refute String.contains?(vcard, "ORG")
      refute String.contains?(vcard, "TITLE")
      refute String.contains?(vcard, "NOTE")
    end

    test "escapes special characters" do
      contact = %{
        display_name: "O'Brien, Jr.",
        first_name: "O'Brien",
        last_name: "Smith; Doe",
        nickname: nil,
        birthdate: nil,
        company: "Foo, Bar & Baz",
        occupation: nil,
        description: "Line 1\nLine 2",
        addresses: [],
        contact_fields: [],
        gender: nil
      }

      vcard = Serializer.serialize(contact)

      assert String.contains?(vcard, "N:Smith\\; Doe;O'Brien;;;\r\n")
      assert String.contains?(vcard, "ORG:Foo\\, Bar & Baz\r\n")
      assert String.contains?(vcard, "NOTE:Line 1\\nLine 2\r\n")
    end
  end

  describe "serialize_many/1" do
    test "concatenates multiple vCards" do
      contacts = [
        %{
          display_name: "Alice",
          first_name: "Alice",
          last_name: "A",
          nickname: nil,
          birthdate: nil,
          company: nil,
          occupation: nil,
          description: nil,
          addresses: [],
          contact_fields: [],
          gender: nil
        },
        %{
          display_name: "Bob",
          first_name: "Bob",
          last_name: "B",
          nickname: nil,
          birthdate: nil,
          company: nil,
          occupation: nil,
          description: nil,
          addresses: [],
          contact_fields: [],
          gender: nil
        }
      ]

      result = Serializer.serialize_many(contacts)
      blocks = String.split(result, "BEGIN:VCARD") |> Enum.reject(&(&1 == ""))
      assert length(blocks) == 2
    end
  end

  describe "escape/1" do
    test "escapes semicolons" do
      assert Serializer.escape("a;b") == "a\\;b"
    end

    test "escapes commas" do
      assert Serializer.escape("a,b") == "a\\,b"
    end

    test "escapes newlines" do
      assert Serializer.escape("a\nb") == "a\\nb"
      assert Serializer.escape("a\r\nb") == "a\\nb"
    end

    test "escapes backslashes" do
      assert Serializer.escape("a\\b") == "a\\\\b"
    end

    test "returns empty string for nil" do
      assert Serializer.escape(nil) == ""
    end
  end
end
