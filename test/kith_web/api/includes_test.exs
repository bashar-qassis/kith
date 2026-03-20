defmodule KithWeb.API.IncludesTest do
  use ExUnit.Case, async: true

  alias KithWeb.API.Includes

  describe "parse_includes/2" do
    test "nil include returns empty list" do
      assert {:ok, []} = Includes.parse_includes(%{}, :contact_show)
    end

    test "empty include returns empty list" do
      assert {:ok, []} = Includes.parse_includes(%{"include" => ""}, :contact_show)
    end

    test "valid includes returns atom list" do
      assert {:ok, [:tags, :notes]} =
               Includes.parse_includes(%{"include" => "tags,notes"}, :contact_show)
    end

    test "invalid include returns error with valid options" do
      assert {:error, msg} =
               Includes.parse_includes(%{"include" => "invalid_thing"}, :contact_show)

      assert msg =~ "Invalid include"
      assert msg =~ "tags"
    end

    test "mixed valid and invalid returns error" do
      assert {:error, msg} =
               Includes.parse_includes(%{"include" => "tags,foobar"}, :contact_show)

      assert msg =~ "foobar"
    end

    test "contact_list has restricted includes" do
      assert {:error, _} =
               Includes.parse_includes(%{"include" => "notes"}, :contact_list)

      assert {:ok, [:tags]} =
               Includes.parse_includes(%{"include" => "tags"}, :contact_list)
    end

    test "trims whitespace from includes" do
      assert {:ok, [:tags, :notes]} =
               Includes.parse_includes(%{"include" => " tags , notes "}, :contact_show)
    end
  end

  describe "included?/2" do
    test "returns true when key is in list" do
      assert Includes.included?([:tags, :notes], :tags)
    end

    test "returns false when key is not in list" do
      refute Includes.included?([:tags], :notes)
    end
  end

  describe "to_preloads/1" do
    test "converts include atoms to preload specs" do
      assert [:contact_fields] = Includes.to_preloads([:contact_fields])
      assert [:tags, :notes] = Includes.to_preloads([:tags, :notes])
    end
  end
end
