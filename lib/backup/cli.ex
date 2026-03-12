defmodule Backup.CLI do
  alias Backup.{Runner, Util}

  def main(argv) do
    {opts, args, _} =
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

    if opts[:help], do: usage()

    workers = opts[:workers] || 4
    retries = opts[:retries] || 2

    case args do
      [src, dst] ->
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
