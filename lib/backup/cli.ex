defmodule Backup.CLI do
  alias Backup.{Runner, Util}

  def main(argv) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        switches: [
          workers: :integer,
          retries: :integer,
          dry_run: :boolean,
          exclude: :keep,
          flags: :string,
          rsync_path: :string,
          help: :boolean
        ],
        aliases: [w: :workers, h: :help, n: :dry_run]
      )

    if opts[:help] do
      usage()
      System.halt(0)
    end

    if invalid != [] do
      Util.error("Unknown options: #{inspect(invalid)}")
      usage()
    end

    workers = max(opts[:workers] || 11, 1)
    retries = max(opts[:retries] || 2, 0)

    case args do
      [src, dst] ->
        src = Path.expand(src)
        dst = Path.expand(dst)

        Runner.run(src, dst, workers, retries, opts)

      _ ->
        usage()
    end
  end

  defp usage do
      IO.puts("""
    backup <src> <dst> [options]

          -w --workers N     parallel rsync workers (default 11)
          --retries N        retries per batch (default 2)
          -n --dry-run       pass --dry-run to rsync
          --exclude PATTERN  repeatable; defaults to .DS_Store
          --flags "..."      extra raw rsync flags
          --rsync-path PATH  explicit rsync binary (must be rsync 3.x)
          -h --help
    """)

    System.halt(1)
  end
end
