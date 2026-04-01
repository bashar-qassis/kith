defmodule KithWeb.ImportWizardLiveTest do
  use KithWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "handle_info/2" do
    test "does not crash on :sync_complete broadcast", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/import")
      send(view.pid, {:sync_complete, %{"status" => "completed", "synced" => 0}})
      # If the process is still alive and renders without error, the fix is working
      assert render(view) =~ "Import Contacts"
    end
  end
end
