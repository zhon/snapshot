defmodule Backup.Sweep do
  @moduledoc """
  Removes destination entries that no longer exist in the source, running at the
  end of every successful sync.

  Why this is not just `rsync --delete`
  ------------------------------------

  The obvious implementation is to pass `--delete` to the transfers this tool
  already runs. That does nothing: batching requires `--files-from`, and rsync
  ignores `--delete` whenever `--files-from` is in play. Verified — deleting a
  file from the source and syncing with `--delete` leaves it at the
  destination, while a plain recursive `rsync -a --delete` removes it.

  So deletion is a second rsync invocation: a recursive dry run with `--delete`
  and no `--files-from`, whose output names every path that would go. We then
  remove exactly those paths. rsync decides what is stale; this module only
  carries it out.

  Doing it this way gets three things right that a hand-rolled scan cannot:

    * **Excludes are honoured.** rsync applies its own `--exclude` patterns,
      so a destination path the user has excluded is never proposed for
      deletion. A scan would have to reimplement pattern matching.

    * **A partially unreadable source cannot trigger a wipe.** If rsync cannot
      read part of the source it exits non-zero (23 on a permission error) and
      says so on stderr. We treat any non-zero exit as "we do not know what is
      stale" and delete nothing at all. Verified: with an unreadable source
      subdirectory rsync still proposed 82 deletions and exited 23 — the
      proposal is not a safety signal, the exit code is. This is what keeps a
      dropped SMB share or an unmounted volume from looking like an empty
      source that legitimately deletes everything.

    * **Directories are handled by rsync, not by us.** A renamed source folder
      is reported as its files plus the directory itself, and rsync already
      knows the order in which that is safe to remove.

  What this does *not* do: it never renames. A folder renamed at the source is
  deleted here and re-copied under its new name. That costs a full re-transfer
  of the folder, which is the deliberate trade for never having to decide that
  one destination folder is the same data as another.
  """

  alias Backup.Util

  @doc """
  Deletes destination entries rsync reports as absent from the source.

  Refuses to delete anything at all if the rsync dry run exits non-zero.
  Returns `{:ok, deleted_paths}` or `{:error, reason, code}`.
  """
  def sweep(src, dst, opts \\ []) do
    src = with_trailing_slash(src)
    dst_arg = with_trailing_slash(dst)
    dst_root = Path.expand(dst)

    case Backup.Rsync.ensure_supported(opts[:rsync_path]) do
      {:ok, exe} ->
        {output, code} = run_dry_run(exe, src, dst_arg, opts)

        cond do
          # An empty (or all-excluded) source is indistinguishable from an
          # unmounted volume whose mount point happens to exist, and rsync
          # deletes the entire destination for it while exiting 0. Refuse.
          empty_source?(exe, src, opts) ->
            report_empty_source(src)
            {:error, :source_appears_empty, 8}

          code != 0 ->
            report_refusal(code, output)
            {:error, :incomplete_source_scan, code}

          true ->
            paths = deletions(output, dst_root)
            remove(paths, dst_root, truthy?(opts[:dry_run]))
            {:ok, paths}
        end

      {:error, reason} ->
        {:error, reason, 7}
    end
  end

  # `-n` makes this a no-op on disk; we are using it purely to ask rsync which
  # paths it would delete. `--itemize-changes` prefixes each with `*deleting`,
  # which is the only line shape we act on -- `.d...p.....` lines are attribute
  # changes and must not be mistaken for deletions.
  defp run_dry_run(exe, src, dst, opts) do
    args =
      ["-a", "-n", "--delete", "--itemize-changes"] ++
        exclude_flags(opts) ++ [src, dst]

    # stdin redirected from /dev/null so a wrapper that reads it cannot hang.
    System.shell(~s("#{exe}" #{Enum.join(args, " ")} </dev/null 2>&1))
  end

  defp exclude_flags(opts) do
    case opts[:exclude] || [".DS_Store"] do
      list when is_list(list) -> Enum.flat_map(list, &["--exclude", to_string(&1)])
      single -> ["--exclude", to_string(single)]
    end
  end

  # Each deletion line looks like:
  #   *deleting   2026/2026-08-01/IMG_0001.jpg
  #   *deleting   2026/2026-08-01/
  # The trailing slash on a directory is rsync's, not ours.
  defp deletions(output, _dst_root) do
    output
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^\*deleting\s+(.+?)\s*$/, line) do
        [_, path] -> [String.trim(path)]
        _ -> []
      end
    end)
  end

  # Files first, then directories deepest-first, so a directory is never
  # removed before the entries inside it.
  defp remove(paths, dst_root, dry_run?) do
    {files, dirs} =
      Enum.split_with(paths, fn p -> not String.ends_with?(p, "/") end)

    sorted =
      files ++ Enum.sort_by(dirs, fn p -> -String.length(String.trim_trailing(p, "/")) end)

    Enum.each(sorted, fn rel -> remove_one(rel, dst_root, dry_run?) end)
  end

  defp remove_one(rel, dst_root, dry_run?) do
    target = Path.expand(Path.join(dst_root, rel))

    # Belt and braces: a path from rsync's output must land inside the
    # destination we were given. rsync will not emit `../`, but this is the
    # one operation here that destroys data, so it is checked anyway.
    if inside?(target, dst_root) do
      if dry_run? do
        Util.warn("would delete  #{rel}")
      else
        delete(target, rel)
      end
    else
      Util.error("refusing to delete #{rel}: resolves outside the destination")
    end
  end

  defp inside?(target, root) do
    String.starts_with?(target, root <> "/")
  end

  defp delete(target, rel) do
    # File.rm removes a symlink itself rather than following it, which is what
    # we want; File.rm_rf covers the directories rsync reported.
    result =
      case File.lstat(target) do
        {:ok, %File.Stat{type: :directory}} -> File.rm_rf(target)
        {:ok, _} -> File.rm(target)
        {:error, reason} -> {:error, reason}
      end

    case result do
      :ok -> Util.info("deleted    #{rel}")
      {:ok, _} -> Util.info("deleted    #{rel}")
      {:error, reason} -> Util.error("could not delete #{rel}: #{inspect(reason)}")
    end
  end

  defp report_refusal(code, output) do
    Util.error(
      "not deleting anything: the source could not be read completely " <>
        "(rsync exited #{code}). Fix the errors below and run again."
    )

    output
    |> String.split("\n")
    |> Enum.filter(&(String.contains?(&1, "rsync:") or String.contains?(&1, "rsync error")))
    |> Enum.each(&Util.error("  " <> String.trim(&1)))
  end

  # True when the source holds no regular files at all, or nothing beyond the
  # excluded patterns -- the shape an unmounted volume leaves behind, which
  # rsync will happily resolve as "delete the entire destination".
  #
  # rsync always itemizes the root itself, so an empty source still prints one
  # `.` line; counting regular files is what separates "nothing here" from
  # "some files".
  #
  # A non-zero exit does NOT mean empty. It means part of the source could not
  # be read, which the caller's own non-zero check handles. Conflating the two
  # would report an unreadable subtree as an empty source.
  defp empty_source?(exe, src, opts) do
    args = ["-a", "-n", "--out-format=%n"] ++ exclude_flags(opts) ++ [src]

    {out, _code} = System.shell(~s("#{exe}" #{Enum.join(args, " ")} </dev/null 2>/dev/null))

    out
    |> String.split("\n")
    |> Enum.count(&Regex.match?(~r/^-/, &1)) == 0
  end

  defp report_empty_source(src) do
    Util.error(
      "not deleting anything: #{src} contains no files rsync would copy. " <>
        "If that is wrong, the volume is probably not mounted."
    )
  end

  defp with_trailing_slash("/" = root), do: root
  defp with_trailing_slash(path), do: path <> "/"

  defp truthy?(false), do: false
  defp truthy?(nil), do: false
  defp truthy?(_), do: true
end