defmodule Backup.SweepTest do
  @moduledoc """
  Sweep removes destination entries that are no longer in the source, but only
  when it is certain which those are.

  Each test here corresponds to a way that certainty can be lost: a source that
  cannot be read, a source that is empty because a volume is not mounted, a
  source that has only the excluded files. In every one of those cases the
  correct behaviour is to delete nothing.
  """
  use ExUnit.Case, async: false

  alias Backup.Sweep

  @rsync Enum.find(
            ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"],
            &match?({:ok, v} when v >= 3, Backup.Rsync.version(&1))
          )

  setup do
    %{src: Briefly.create!(directory: true), dst: Briefly.create!(directory: true)}
  end

  defp count_files(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.count(&(File.lstat(&1) == {:ok, %File.Stat{type: :regular}}))
  end

  defp write(dir, rel) do
    path = Path.join(dir, rel)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, "x")
  end

  defp sync!(src, dst) do
    System.shell(~s("#{@rsync}" -a "#{src}/" "#{dst}/" </dev/null))
  end

  defp sweep(src, dst, opts \\ []) do
    if @rsync do
      Sweep.sweep(src, dst, Keyword.put(opts, :rsync_path, @rsync))
    else
      {:error, :no_rsync, 0}
    end
  end

  describe "deleting what is genuinely gone" do
    @tag :rsync
    test "removes a destination file with no source counterpart", %{src: src, dst: dst} do
      write(src, "keep.txt")
      write(dst, "keep.txt")
      write(dst, "stale.txt")

      assert {:ok, deleted} = sweep(src, dst)

      assert "stale.txt" in deleted
      refute File.exists?(Path.join(dst, "stale.txt"))
      assert File.exists?(Path.join(dst, "keep.txt"))
    end

    @tag :rsync
    test "removes a directory deleted at the source, files and all", %{src: src, dst: dst} do
      File.mkdir_p!(Path.join(dst, "gone"))
      write(dst, "gone/one.jpg")
      write(dst, "gone/two.jpg")
      write(src, "other.txt")

      assert {:ok, _} = sweep(src, dst)

      refute File.exists?(Path.join(dst, "gone")),
             "a directory absent from the source should be removed entirely"
    end

    # A rename is not detected as one: the old destination directory is deleted
    # and the new one arrives by copy. That costs a re-transfer and is the
    # deliberate trade for never having to decide that two folders hold the
    # same data.
    @tag :rsync
    test "a renamed source directory is deleted and recopied, not renamed", %{src: src, dst: dst} do
      # The old name exists only at the destination; the new name only at the
      # source. That is what a rename looks like to rsync.
      for i <- 1..3, do: write(dst, "old-name/#{i}.jpg")
      for i <- 1..3, do: write(src, "new-name/#{i}.jpg")

      assert {:ok, deleted} = sweep(src, dst)

      assert "old-name/" in deleted
      refute File.exists?(Path.join(dst, "old-name"))
      refute File.exists?(Path.join(dst, "new-name")),
             "the sweep only deletes; copying is the sync's job"
    end

    @tag :rsync
    test "leaves an already-synced tree alone, and stays idempotent", %{src: src, dst: dst} do
      File.mkdir_p!(Path.join(src, "sub"))
      write(src, "a.txt")
      write(src, "sub/b.txt")

      # Model a completed sync, then confirm the sweep finds nothing to do.
      assert {_out, 0} = sync!(src, dst)
      before = count_files(dst)

      assert {:ok, first} = sweep(src, dst)
      assert {:ok, second} = sweep(src, dst)

      assert first == []
      assert second == []
      assert count_files(dst) == before
    end

    @tag :rsync
    test "a second sweep deletes nothing further", %{src: src, dst: dst} do
      write(src, "keep.txt")
      write(dst, "stale.txt")

      assert {:ok, first} = sweep(src, dst)
      assert length(first) > 0

      File.write!(Path.join(dst, "keep.txt"), "x")
      assert {_out, 0} = sync!(src, dst)

      assert {:ok, second} = sweep(src, dst)
      assert second == []
    end
  end

  describe "refusing to delete when the source cannot be trusted" do
    @tag :rsync
    test "deletes nothing when the source is empty", %{dst: dst} do
      write(dst, "precious.jpg")
      write(dst, "also-precious.jpg")
      src = Briefly.create!(directory: true)
      before = count_files(dst)

      assert {:error, :source_appears_empty, _} = sweep(src, dst)

      assert count_files(dst) == before,
             "an empty source is what an unmounted volume looks like"
    end

    @tag :rsync
    test "deletes nothing when a source subdirectory cannot be read", %{src: src, dst: dst} do
      File.mkdir_p!(Path.join(src, "locked"))
      write(src, "locked/hidden.jpg")
      write(src, "readable.jpg")
      File.mkdir_p!(Path.join(dst, "locked"))
      write(dst, "locked/hidden.jpg")
      write(dst, "readable.jpg")
      File.chmod!(Path.join(src, "locked"), 0o000)
      on_exit(fn -> File.chmod(Path.join(src, "locked"), 0o755) end)
      before = count_files(dst)

      result = sweep(src, dst)
      File.chmod!(Path.join(src, "locked"), 0o755)

      assert {:error, _reason, _code} = result
      assert count_files(dst) == before
    end

    @tag :rsync
    test "deletes nothing when every source file is excluded", %{dst: dst} do
      src = Briefly.create!(directory: true)
      write(src, "junk.log")
      write(dst, "precious.jpg")
      before = count_files(dst)

      assert {:error, :source_appears_empty, _} = sweep(src, dst, exclude: ["*.log"])

      assert count_files(dst) == before
    end
  end

  describe "excludes" do
    @tag :rsync
    test "a destination path matching --exclude is not deleted", %{src: src, dst: dst} do
      File.mkdir_p!(Path.join(dst, "my-notes"))
      write(dst, "my-notes/notes.txt")
      write(src, "photo.jpg")

      assert {:ok, deleted} = sweep(src, dst, exclude: ["my-notes*"])

      assert File.exists?(Path.join(dst, "my-notes/notes.txt"))
      refute Enum.any?(deleted, &String.starts_with?(&1, "my-notes"))
    end

    @tag :rsync
    test ".DS_Store is excluded by default", %{src: src, dst: dst} do
      write(src, "photo.jpg")
      write(dst, ".DS_Store")

      assert {:ok, _} = sweep(src, dst)

      assert File.exists?(Path.join(dst, ".DS_Store"))
    end
  end

  describe "preview" do
    @tag :rsync
    test "dry run reports without deleting", %{src: src, dst: dst} do
      write(src, "keep.txt")
      write(dst, "stale.txt")
      before = count_files(dst)

      assert {:ok, deleted} = sweep(src, dst, dry_run: true)

      assert "stale.txt" in deleted
      assert count_files(dst) == before
    end
  end

  describe "rsync requirement" do
    test "refuses the macOS openrsync and deletes nothing", %{src: src, dst: dst} do
      write(src, "a.txt")
      write(dst, "stale.txt")
      before = count_files(dst)

      assert {:error, _reason, _code} = Sweep.sweep(src, dst, rsync_path: "/usr/bin/rsync")
      assert count_files(dst) == before
    end
  end

  describe "path safety" do
    # rsync will not emit a path outside the destination, but this is the one
    # operation here that destroys data, so the invariant is asserted directly.
    @tag :rsync
    test "only paths inside the destination are ever removed", %{src: src, dst: dst} do
      outside = Briefly.create!(directory: true)
      write(outside, "untouched.txt")
      write(src, "a.txt")
      write(dst, "stale.txt")
      before = count_files(outside)

      assert {:ok, deleted} = sweep(src, dst)

      assert Enum.all?(deleted, &(not String.contains?(&1, "..")))
      assert count_files(outside) == before
    end
  end
end