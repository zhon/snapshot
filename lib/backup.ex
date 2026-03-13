defmodule Backup.Runner do
  alias Backup.{Scanner, Rsync, Retry, Util}

  def run(src, dst, workers, retries, opts) do
    with :ok <- Util.check(File.dir?(src), "Source directory missing", 2),
         :ok <- Util.check(File.dir?(dst), "Destination missing", 3) do

      Util.info("Scanning files...")

      src
      |> Scanner.scan()
      |> Stream.chunk_every(200)
      |> Task.async_stream(
        fn batch ->
          Retry.attempt(fn ->
            Rsync.sync_batch(batch, src, dst, opts)
          end, retries)
        end,
        max_concurrency: workers,
        timeout: :infinity,
        ordered: false
      )
      |> Stream.run()

      Util.success("✔ all sync jobs finished")
    else
      {:error, msg, code} ->
        Util.error(msg)
        System.halt(code)
    end
  end
end
