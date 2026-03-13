defmodule Backup.CLI do
  alias Backup.{Runner, Util}

  def main(argv) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        switches: [
          workers: :integer,
          retries: :integer,
          dry_run: :boolean,
          delete: :boolean,
          help: :boolean
        ],
        aliases: [w: :workers, h: :help]
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

      -w --workers N
      --retries N
      --dry-run
      --delete
      -h --help
    """)

    System.halt(1)
  end
end
