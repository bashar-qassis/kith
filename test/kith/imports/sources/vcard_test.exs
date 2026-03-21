defmodule Kith.Imports.Sources.VCardTest do
  use Kith.DataCase, async: true

  alias Kith.Imports.Sources.VCard, as: VCardSource

  describe "name/0" do
    test "returns source name" do
      assert VCardSource.name() == "vCard"
    end
  end

  describe "file_types/0" do
    test "returns accepted file types" do
      assert VCardSource.file_types() == [".vcf"]
    end
  end

  describe "supports_api?/0" do
    test "returns false" do
      refute VCardSource.supports_api?()
    end
  end

  describe "validate_file/1" do
    test "validates a proper vCard file" do
      data = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Jane Doe\r\nEND:VCARD\r\n"
      assert {:ok, _} = VCardSource.validate_file(data)
    end

    test "rejects invalid data" do
      assert {:error, _} = VCardSource.validate_file("not a vcard")
    end
  end

  describe "parse_summary/1" do
    test "returns contact count" do
      data = "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Doe;Jane;;;\r\nFN:Jane Doe\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:3.0\r\nN:Smith;John;;;\r\nFN:John Smith\r\nEND:VCARD\r\n"
      assert {:ok, %{contacts: 2}} = VCardSource.parse_summary(data)
    end
  end
end
