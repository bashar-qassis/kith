defmodule Kith.DAV.XMLBuilderTest do
  use ExUnit.Case, async: true

  alias Kith.DAV.XMLBuilder

  describe "address_data/1" do
    test "wraps vCard in CDATA section" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Test\r\nEND:VCARD\r\n"
      result = XMLBuilder.address_data(vcard)

      assert result == "<card:address-data><![CDATA[#{vcard}]]></card:address-data>"
    end

    test "preserves CRLF line endings inside CDATA" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nBDAY:1990-06-15\r\nEND:VCARD\r\n"
      result = XMLBuilder.address_data(vcard)

      assert result =~ "\r\n"
      refute result =~ "&amp;"
    end
  end
end
