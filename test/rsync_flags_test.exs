defmodule Backup.RsyncFlagsTest do
  use ExUnit.Case, async: true

  alias Backup.Rsync

  test "returns base flags with no options" do
    flags = Rsync.flags([])

    assert "-a" in flags
    assert "-R" in flags
    assert "--human-readable" in flags
    assert "--info=progress2" in flags
  end

  test "adds boolean flags" do
    flags = Rsync.flags(delete: true, dry_run: true)

    assert "--delete" in flags
    assert "--dry-run" in flags
  end

  test "does not add boolean flags when false or missing" do
    flags = Rsync.flags(delete: false)

    refute "--delete" in flags
  end

  # Regression: the old `maybe/3` had no clause for `false`, so an explicit
  # false raised FunctionClauseError and crashed the run.
  test "explicit false does not raise" do
    assert is_list(Rsync.flags(delete: false, dry_run: false))
  end

  test "adds extra flags from a string" do
    flags = Rsync.flags(flags: "--size-only --ignore-existing")

    assert "--size-only" in flags
    assert "--ignore-existing" in flags
  end

  test "adds extra flags from a list" do
    flags = Rsync.flags(flags: ["--size-only"])

    assert "--size-only" in flags
  end

  test "removes duplicates" do
    flags = Rsync.flags(flags: "--delete", delete: true)

    assert Enum.count(flags, &(&1 == "--delete")) == 1
  end

  test "excludes default to .DS_Store" do
    flags = Rsync.flags([])

    assert "--exclude" in flags
    assert ".DS_Store" in flags
  end

  test "supports multiple excludes" do
    flags = Rsync.flags(exclude: ["*.log", "tmp"])

    assert "*.log" in flags
    assert "tmp" in flags
    refute ".DS_Store" in flags
  end
end