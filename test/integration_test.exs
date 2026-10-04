defmodule Backup.IntegrationTest do
  @moduledoc """
  End-to-end coverage for the worker/runner wiring — the modules where the
  real bugs lived. Skipped when no real rsync 3.x is available, since macOS
  ships openrsync.
  """

  use ExUnit.Case, async: false

  alias Backup.RsyncWorker

  setup_all do
    case real_rsync() do
      nil -> {:ok, skip: "no real rsync 3.x found"}
      exe -> {:ok, exe: exe}
    end
  end

  setup context do
    src = Briefly.create!(directory: true)
    dst = Briefly.create!(directory: true)
    %{src: src, dst: dst, exe: context[:exe]}
  end

  @tag :integration
  test "copies a nested tree and reports rsync's real exit code", %{
    src: src,
    dst: dst,
    exe: exe
  } do
    File.mkdir_p!(Path.join(src, "a/b"))
    File.write!(Path.join(src, "top.txt"), "top")
    File.write!(Path.join(src, "a/b/deep.txt"), "deep")

    files = Enum.to_list(Backup.Scanner.scan(src))
    assert length(files) == 2

    {:ok, worker} = RsyncWorker.start(src, dst, rsync_path: exe)
    assert :ok = RsyncWorker.send_batch(worker, files)
    assert {:ok, 0} = RsyncWorker.finish(worker)

    assert File.read!(Path.join(dst, "top.txt")) == "top"
    assert File.read!(Path.join(dst, "a/b/deep.txt")) == "deep"
  end

  # Regression: finish/1 used to send an empty string instead of closing stdin,
  # so rsync never saw EOF and the process hung forever.
  @tag :integration
  test "finish completes instead of hanging", %{src: src, dst: dst, exe: exe} do
    File.write!(Path.join(src, "one.txt"), "one")

    {:ok, worker} = RsyncWorker.start(src, dst, rsync_path: exe)
    :ok = RsyncWorker.send_batch(worker, Enum.to_list(Backup.Scanner.scan(src)))

    task = Task.async(fn -> RsyncWorker.finish(worker) end)

    assert {:ok, 0} = Task.await(task, 30_000)
  end

  @tag :integration
  test "surfaces a non-zero rsync exit code", %{src: src, dst: dst} do
    File.write!(Path.join(src, "one.txt"), "one")
    fake = write_failing_rsync(src, dst)

    {:ok, worker} = RsyncWorker.start(src, dst, rsync_path: fake)
    :ok = RsyncWorker.send_batch(worker, Enum.to_list(Backup.Scanner.scan(src)))

    assert {:ok, 23} = RsyncWorker.finish(worker)
  end

  @tag :integration
  test "start refuses openrsync without raising", %{src: src, dst: dst} do
    assert {:error, _} = RsyncWorker.start(src, dst, rsync_path: "/usr/bin/rsync")
  end

  # The reason `--delete` was removed from the flag list. With `--files-from`
  # (how this tool streams batches) rsync ignores `--delete` entirely, so the
  # flag reported a cleanup that never happened. Proven here by contrast: the
  # same tree synced the way this tool syncs, then with a plain recursive
  # rsync.
  @tag :integration
  test "rsync --delete is a no-op with --files-from", %{src: src, dst: dst, exe: exe} do
    File.mkdir_p!(Path.join(src, "sub"))
    File.write!(Path.join(src, "sub/gone.txt"), "gone")

    # First sync, so the destination holds the file we later delete.
    {:ok, worker} = RsyncWorker.start(src, dst, rsync_path: exe)
    :ok = RsyncWorker.send_batch(worker, Enum.to_list(Backup.Scanner.scan(src)))
    assert {:ok, 0} = RsyncWorker.finish(worker)
    assert File.exists?(Path.join(dst, "sub/gone.txt"))

    File.rm!(Path.join(src, "sub/gone.txt"))

    # Sync again. Even asking rsync to delete cannot remove it, because
    # --files-from is in play.
    {:ok, worker} = RsyncWorker.start(src, dst, rsync_path: exe, flags: "--delete")
    :ok = RsyncWorker.send_batch(worker, Enum.to_list(Backup.Scanner.scan(src)))
    assert {:ok, 0} = RsyncWorker.finish(worker)

    assert File.exists?(Path.join(dst, "sub/gone.txt")),
           "expected --delete to be ignored; if this now fails, rsync changed and --delete may work"

    # Contrast: a plain recursive rsync -a --delete does remove it.
    {_, 0} = System.shell(~s("#{exe}" -a --delete "#{src}/" "#{dst}/" </dev/null))
    refute File.exists?(Path.join(dst, "sub/gone.txt"))
  end

  # A stub that passes the version probe but fails the transfer, so we can
  # assert exit-code propagation without corrupting anything real.
  defp write_failing_rsync(_src, dst) do
    path = Path.join(dst, "fake-rsync")
    script = """
    #!/bin/sh
    for a in "$@"; do
      if [ "$a" = "--version" ]; then
        echo "rsync  version 3.5.0  protocol version 32"
        exit 0
      fi
    done
    cat >/dev/null
    exit 23
    """

    File.write!(path, script)
    File.chmod!(path, 0o755)
    path
  end

  defp real_rsync do
    Enum.find(["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"], fn path ->
      match?({:ok, v} when v >= 3, version(path))
    end)
  end

  defp version(path) do
    if File.exists?(path), do: Backup.Rsync.version(path), else: {:error, :missing}
  rescue
    _ -> {:error, :error}
  end
end