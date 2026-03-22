defmodule Kith.Workers.ApiSupplementWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Workers.ApiSupplementWorker

  describe "perform/1" do
    test "discards when import not found" do
      assert {:discard, _} =
               perform_job(ApiSupplementWorker, %{
                 import_id: 999_999,
                 contact_id: 1,
                 source_contact_id: "uuid",
                 key: "first_met_details"
               })
    end
  end
end
