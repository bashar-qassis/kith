defmodule KithWeb.API.PaginationTest do
  use ExUnit.Case, async: true

  alias KithWeb.API.Pagination

  describe "decode_cursor/1" do
    test "nil returns :start" do
      assert Pagination.decode_cursor(nil) == :start
    end

    test "empty string returns :start" do
      assert Pagination.decode_cursor("") == :start
    end

    test "valid cursor returns {:ok, id}" do
      cursor = Base.url_encode64(Jason.encode!(%{"id" => 42}), padding: false)
      assert Pagination.decode_cursor(cursor) == {:ok, 42}
    end

    test "invalid base64 returns error" do
      assert Pagination.decode_cursor("not-valid-base64!!!") == {:error, :invalid_cursor}
    end

    test "valid base64 but invalid JSON returns error" do
      cursor = Base.url_encode64("not json", padding: false)
      assert Pagination.decode_cursor(cursor) == {:error, :invalid_cursor}
    end

    test "valid JSON but missing id returns error" do
      cursor = Base.url_encode64(Jason.encode!(%{"foo" => "bar"}), padding: false)
      assert Pagination.decode_cursor(cursor) == {:error, :invalid_cursor}
    end
  end
end
