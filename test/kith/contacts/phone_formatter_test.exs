defmodule Kith.Contacts.PhoneFormatterTest do
  use ExUnit.Case, async: true

  alias Kith.Contacts.PhoneFormatter

  describe "normalize/1" do
    test "returns nil for nil" do
      assert {:ok, nil} = PhoneFormatter.normalize(nil)
    end

    test "returns nil for empty string" do
      assert {:ok, nil} = PhoneFormatter.normalize("")
    end

    test "preserves E.164 input" do
      assert {:ok, "+12345678901"} = PhoneFormatter.normalize("+12345678901")
    end

    test "adds country code to 10-digit US number" do
      assert {:ok, "+12345678901"} = PhoneFormatter.normalize("2345678901")
    end

    test "strips formatting and normalizes" do
      assert {:ok, "+12345678901"} = PhoneFormatter.normalize("(234) 567-8901")
    end

    test "handles 11-digit number starting with 1" do
      assert {:ok, "+12345678901"} = PhoneFormatter.normalize("12345678901")
    end

    test "handles international number with +" do
      assert {:ok, "+442079460958"} = PhoneFormatter.normalize("+44 20 7946 0958")
    end

    test "adds + to 7+ digit numbers without it" do
      assert {:ok, "+1234567"} = PhoneFormatter.normalize("1234567")
    end

    test "preserves short numbers as-is" do
      assert {:ok, "12345"} = PhoneFormatter.normalize("12345")
    end

    test "handles whitespace" do
      assert {:ok, "+12345678901"} = PhoneFormatter.normalize("  +1 234 567 8901  ")
    end
  end

  describe "format/2" do
    test "e164 returns as-is" do
      assert "+12345678901" = PhoneFormatter.format("+12345678901", "e164")
    end

    test "raw returns as-is" do
      assert "+12345678901" = PhoneFormatter.format("+12345678901", "raw")
    end

    test "national formats US number" do
      assert "(234) 567-8901" = PhoneFormatter.format("+12345678901", "national")
    end

    test "international formats US number" do
      assert "+1 234-567-8901" = PhoneFormatter.format("+12345678901", "international")
    end

    test "national falls back for non-US numbers" do
      assert "+442079460958" = PhoneFormatter.format("+442079460958", "national")
    end

    test "international falls back for non-US numbers" do
      assert "+442079460958" = PhoneFormatter.format("+442079460958", "international")
    end

    test "nil returns nil" do
      assert nil == PhoneFormatter.format(nil, "e164")
    end
  end
end
