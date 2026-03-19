defmodule Kith.SentryEventHandlerTest do
  use ExUnit.Case, async: true

  alias Kith.SentryEventHandler

  describe "scrub_params/1" do
    test "scrubs password fields" do
      params = %{"password" => "secret123", "email" => "user@example.com"}
      result = SentryEventHandler.scrub_params(params)

      assert result["password"] == "[FILTERED]"
      assert result["email"] == "user@example.com"
    end

    test "scrubs all sensitive keys" do
      params = %{
        "password" => "secret",
        "password_confirmation" => "secret",
        "token" => "abc123",
        "api_key" => "key-123",
        "secret" => "my-secret",
        "current_password" => "old",
        "new_password" => "new",
        "safe_field" => "visible"
      }

      result = SentryEventHandler.scrub_params(params)

      assert result["password"] == "[FILTERED]"
      assert result["password_confirmation"] == "[FILTERED]"
      assert result["token"] == "[FILTERED]"
      assert result["api_key"] == "[FILTERED]"
      assert result["secret"] == "[FILTERED]"
      assert result["current_password"] == "[FILTERED]"
      assert result["new_password"] == "[FILTERED]"
      assert result["safe_field"] == "visible"
    end

    test "scrubs nested maps" do
      params = %{"user" => %{"password" => "secret", "name" => "Bob"}}
      result = SentryEventHandler.scrub_params(params)

      assert result["user"]["password"] == "[FILTERED]"
      assert result["user"]["name"] == "Bob"
    end

    test "handles non-map values" do
      assert SentryEventHandler.scrub_params("string") == "string"
      assert SentryEventHandler.scrub_params(nil) == nil
    end
  end
end
