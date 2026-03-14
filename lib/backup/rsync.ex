defmodule Backup.Rsync do
  # Build rsync flags
  def flags(opts) do
    base = [
      "-a",
      "-R",                     # preserve relative paths
      "--human-readable",
      "--info=progress2"
    ]

    base
    |> maybe("--dry-run", opts[:dry_run])
    |> maybe("--delete", opts[:delete])
    |> maybe_excludes(opts)
  end

  defp maybe(list, _flag, nil), do: list
  defp maybe(list, flag, true), do: list ++ [flag]

  defp maybe_excludes(list, opts) do
    excludes = opts[:exclude] || [".DS_Store"]
    Enum.reduce(excludes, list, fn pattern, acc -> acc ++ ["--exclude", pattern] end)
  end
end
