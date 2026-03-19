defmodule Kith.GeocodingTest do
  use Kith.DataCase, async: true

  alias Kith.Geocoding

  describe "enabled?/0" do
    test "returns false when env vars not set" do
      # By default in test, ENABLE_GEOLOCATION and LOCATION_IQ_API_KEY are not set
      refute Geocoding.enabled?()
    end
  end

  describe "geocode/1 when not enabled" do
    test "returns not_enabled error" do
      assert {:error, :not_enabled} = Geocoding.geocode("123 Main St")
    end
  end

  describe "install_fuse/0" do
    test "installs without error" do
      assert :ok = Geocoding.install_fuse()
    end
  end
end
