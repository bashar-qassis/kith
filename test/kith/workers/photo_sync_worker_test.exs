defmodule Kith.Workers.PhotoSyncWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Workers.PhotoSyncWorker

  describe "perform/1" do
    test "discards when import not found" do
      assert {:discard, _} =
               perform_job(PhotoSyncWorker, %{
                 import_id: 999_999,
                 photo_id: 1,
                 source_photo_id: "uuid"
               })
    end
  end
end
