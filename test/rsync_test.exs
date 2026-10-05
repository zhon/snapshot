defmodule Snapshot.RsyncTest do
  use ExUnit.Case, async: true

  alias Snapshot.Rsync

  # macOS ships openrsync, which this tool must refuse.
  test "rejects openrsync" do
    if System.find_executable("rsync") do
      assert {:error, _} = Rsync.ensure_supported("/usr/bin/rsync")
    end
  end

  test "accepts a real rsync 3.x" do
    if real_rsync() do
      assert {:ok, path} = Rsync.ensure_supported(real_rsync())
      assert is_binary(path)
    end
  end

  test "reports a missing binary" do
    assert {:error, "rsync not found at /nonexistent/rsync-xyz"} =
             Rsync.ensure_supported("/nonexistent/rsync-xyz")
  end

  defp real_rsync do
    Enum.find(["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"], fn path ->
      match?({:ok, v} when v >= 3, safe_version(path))
    end)
  end

  defp safe_version(path) do
    if File.exists?(path), do: Rsync.version(path), else: {:error, :missing}
  rescue
    _ -> {:error, :error}
  end
end