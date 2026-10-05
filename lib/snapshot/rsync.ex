defmodule Snapshot.Rsync do
  @moduledoc """
  Builds and validates the rsync command line.

  Relevant rsync exit codes (per `man rsync` "EXIT VALUES"):

  - `0` — success
  - `23` — partial transfer (some files failed to copy, usually permissions)
  - `24` — a file vanished from the source during transfer
  - `25` — the `--max-errors` limit was hit

  This tool treats any non-zero exit as a hard failure for both regular
  sync batches and the deletion sweep, so that stale state is never
  silently accepted as a successful snapshot.
  """

  @base ["-a", "-R", "--human-readable", "--info=progress2", "--partial"]

  @bools [{"--dry-run", :dry_run}]

  alias Snapshot.Util

  @doc """
  Verifies the rsync we are about to shell out to is a real rsync.

  macOS ships `/usr/bin/rsync` as openrsync, a partial reimplementation that
  rejects `--info=progress2` and `--from0`. It exits immediately with a usage
  message, which used to surface as an `:epipe` crash after zero files copied.
  Returns `{:ok, path}` or `{:error, message}`.
  """
  def ensure_supported(rsync_path \\ nil) do
    case rsync_path || System.find_executable("rsync") do
      nil ->
        {:error, "rsync not found in PATH"}

      exe ->
        if File.exists?(exe) do
          check_version(exe)
        else
          {:error, "rsync not found at #{exe}"}
        end
    end
  end

  defp check_version(exe) do
    case version(exe) do
      {:ok, version} when version >= 3 ->
        {:ok, exe}

      {:ok, version} ->
        {:error,
         "#{exe} is rsync #{version}; this tool needs rsync 3.x " <>
           "(macOS ships openrsync 2.6.9 at /usr/bin/rsync — " <>
           "install a real one with `brew install rsync`)"}

      {:error, reason} ->
        {:error, "could not run #{exe}: #{inspect(reason)}"}
    end
  end

  @doc "Returns the numeric rsync version, rejecting openrsync."
  def version(exe) do
    # Run under `sh -c` with stdin explicitly redirected from /dev/null:
    # System.cmd/3 inherits this process's stdin, so a wrapper that reads stdin
    # would otherwise block forever when run from a terminal.
    case System.shell("#{exe} --version </dev/null 2>&1") do
      {out, 0} ->
        cond do
          String.contains?(out, "openrsync") ->
            {:error, :openrsync}

          true ->
            case Regex.run(~r/rsync\s+version\s+(\d+)\./, out) do
              [_, digits] -> {:ok, String.to_integer(digits)}
              _ -> {:error, :unparseable}
            end
        end

      {_, code} ->
        {:error, {:exit_status, code}}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Builds the full rsync flag list.

  Boolean flags are only added when truthy; `:flags` is an optional raw string
  of extra flags; `:exclude` defaults to `.DS_Store`.

  `--delete` is deliberately NOT passed through. Combined with `--files-from`
  it is a silent no-op, so it gave false confidence without deleting anything.
  Verified: deleting a file from the source and syncing with `--delete` left
  that file at the destination, while a plain recursive `rsync -a --delete`
  (no `--files-from`) removed it. Removing the flag changes no behavior — it
  stops implying a cleanup that was never happening. Destination pruning is
  not implemented here; use the `--delete` CLI flag of this tool instead, which
  runs a separate dedicated rsync invocation (see `Snapshot.Sweep`).

  Note: passing `--delete` via `--flags` will also be stripped by `Enum.uniq/1`,
  so this is not a supported workaround for the `--files-from` interaction.
  """
  def flags(opts) do
    booleans = Enum.filter(@bools, fn {_flag, key} -> Util.truthy(opts[key]) end)

    extras = split_flags(opts[:flags])
    excludes = List.wrap(opts[:exclude] || [".DS_Store"])

    # Deduped so `--delete` (or any other flag) cannot be passed twice when it
    # is both a boolean and listed in `:flags`.
    plain = @base ++ Enum.map(booleans, &elem(&1, 0)) ++ extras

    Enum.uniq(plain) ++ Enum.flat_map(excludes, &["--exclude", to_string(&1)])
  end

  defp split_flags(nil), do: []
  defp split_flags(flags) when is_binary(flags), do: String.split(flags, ~r/\s+/, trim: true)
  defp split_flags(flags) when is_list(flags), do: Enum.map(flags, &to_string/1)
end