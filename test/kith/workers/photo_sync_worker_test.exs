defmodule Kith.Workers.PhotoBatchSyncWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Workers.PhotoBatchSyncWorker

  describe "perform/1" do
    test "discards when import not found" do
      assert {:discard, _} =
               perform_job(PhotoBatchSyncWorker, %{import_id: 999_999})
    end
  end
end
