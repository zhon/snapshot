defmodule Backup.RsyncFlagsTest do
  use ExUnit.Case, async: true

  alias Backup.Rsync

  test "returns base flags with no options" do
    flags = Rsync.flags([])

    assert "-a" in flags
    assert "--human-readable" in flags
    assert "--append-verify" in flags
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

  test "adds value flags" do
    flags = Rsync.flags(bwlimit: 1000)

    assert "--bwlimit=1000" in flags
  end

  test "adds multi flags" do
    flags = Rsync.flags(exclude: ["tmp", "*.log"])

    assert "--exclude=tmp" in flags
    assert "--exclude=*.log" in flags
  end

  test "splits extra flags string" do
    flags = Rsync.flags(flags: "--size-only --ignore-existing")

    assert "--size-only" in flags
    assert "--ignore-existing" in flags
  end

  test "removes duplicates" do
    flags = Rsync.flags(flags: "--delete", delete: true)

    assert Enum.count(flags, &(&1 == "--delete")) == 1
  end
end
