defmodule Snapshot.RsyncFlagsTest do
  use ExUnit.Case, async: true

  alias Snapshot.Rsync

  test "returns base flags with no options" do
    flags = Rsync.flags([])

    assert "-a" in flags
    assert "-R" in flags
    assert "--human-readable" in flags
    assert "--info=progress2" in flags
  end

  test "adds dry-run" do
    flags = Rsync.flags(dry_run: true)

    assert "--dry-run" in flags
  end

  # `--delete` is a silent no-op when combined with `--files-from`, which is
  # how this tool streams batches. It must never reach rsync: it reads as
  # "stale files are removed" while removing nothing. See the integration test
  # "rsync --delete is a no-op with --files-from" for the proof.
  test "never passes --delete through to rsync" do
    refute "--delete" in Rsync.flags(delete: true)
  end

  test "does not add boolean flags when false or missing" do
    flags = Rsync.flags(dry_run: false)

    refute "--dry-run" in flags
  end

  # Regression: the old `maybe/3` had no clause for `false`, so an explicit
  # false raised FunctionClauseError and crashed the run.
  test "explicit false does not raise" do
    assert is_list(Rsync.flags(dry_run: false))
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
    flags = Rsync.flags(flags: "--size-only --size-only", dry_run: true)

    assert Enum.count(flags, &(&1 == "--size-only")) == 1
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