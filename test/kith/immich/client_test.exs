defmodule Kith.Immich.ClientTest do
  use Kith.DataCase, async: true

  alias Kith.Immich.Client

  # These tests verify error handling paths without hitting a real Immich instance.
  # Integration tests with a mock Immich API would use Req.Test or Bypass.

  describe "list_people/2 error handling" do
    test "returns network_error for unreachable host" do
      assert {:error, _reason} = Client.list_people("http://127.0.0.1:1", "fake-key")
    end
  end
end
