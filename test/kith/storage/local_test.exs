defmodule Kith.Storage.LocalTest do
  use Kith.DataCase, async: true

  alias Kith.Storage.Local

  @test_dir "priv/uploads/test/local_test"

  setup do
    # Ensure clean test directory
    path = Path.join(File.cwd!(), @test_dir)
    File.rm_rf!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    :ok
  end

  describe "upload/3" do
    test "copies file to correct location" do
      # Create a temp source file
      source = Path.join(System.tmp_dir!(), "test_upload_#{System.unique_integer([:positive])}.txt")
      File.write!(source, "hello world")

      key = "#{@test_dir}/test_file.txt"
      assert {:ok, ^key} = Local.upload(source, key)
      assert File.exists?(Local.full_path(key))

      File.rm!(source)
    end
  end

  describe "upload_binary/3" do
    test "writes binary to correct location" do
      key = "#{@test_dir}/binary_test.txt"
      assert {:ok, ^key} = Local.upload_binary("binary content", key)
      assert File.read!(Local.full_path(key)) == "binary content"
    end

    test "creates directories automatically" do
      key = "#{@test_dir}/deep/nested/dir/file.txt"
      assert {:ok, ^key} = Local.upload_binary("content", key)
      assert File.exists?(Local.full_path(key))
    end
  end

  describe "delete/1" do
    test "removes file from disk" do
      key = "#{@test_dir}/to_delete.txt"
      {:ok, _} = Local.upload_binary("content", key)
      assert File.exists?(Local.full_path(key))

      assert :ok = Local.delete(key)
      refute File.exists?(Local.full_path(key))
    end

    test "returns error for missing file" do
      assert {:error, :not_found} = Local.delete("#{@test_dir}/nonexistent.txt")
    end
  end

  describe "url/1" do
    test "returns relative URL path" do
      assert Local.url("1/photos/abc.jpg") == "/uploads/1/photos/abc.jpg"
    end
  end
end
