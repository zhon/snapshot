defmodule Backup.Runner do
  alias Backup.{Scanner, RsyncWorker, Retry, Util}

  def run(src, dst, workers, retries, opts) do
    with :ok <- Util.check(File.dir?(src), "Source directory missing", 2),
         :ok <- Util.check(File.dir?(dst), "Destination missing", 3) do

      Util.info("Scanning files...")

      # Start persistent workers
      ports =
        for _ <- 1..workers do
          port = RsyncWorker.start(src, dst, opts)
          RsyncWorker.listen(port)
          port
        end

      # ETS table for progress
      progress_table = :ets.new(:progress, [:named_table, :public])
      :ets.insert(progress_table, {:done, 0})
      :ets.insert(progress_table, {:total, 0})

      # Stream batches
      Scanner.scan(src)
      |> Stream.chunk_every(200)
      |> Stream.each(fn batch ->
        # Increment total batches
        total_batches = :ets.update_counter(progress_table, :total, {2, 1}, {:total, 0})
        idx = rem(total_batches - 1, length(ports))
        port = Enum.at(ports, idx)

        Retry.attempt(fn ->
          RsyncWorker.send_batch(port, batch, src)
          update_progress(progress_table)
        end, retries)
      end)
      |> Stream.run()

      # Finish all workers
      Enum.each(ports, &RsyncWorker.finish/1)

      Util.success("✔ all sync jobs finished")
    else
      {:error, msg, code} ->
        Util.error(msg)
        System.halt(code)
    end
  end

  defp update_progress(table) do
    done = :ets.update_counter(table, :done, 1)
    [{:total, total}] = :ets.lookup(table, :total)
    percent = if total > 0, do: Float.round(done / total * 100, 1), else: 0.0
    IO.write("\r#{done}/#{total} batches (#{percent}%)")
  end
end
