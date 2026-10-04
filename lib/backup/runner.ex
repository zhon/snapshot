defmodule Backup.Runner do
  @moduledoc """
  Scans a source tree and distributes batches across persistent rsync workers.

  Progress is reported per *file*, and a failure in any batch fails the whole
  run with a non-zero exit code. A backup that reports success while silently
  dropping files is worse than one that fails loudly.
  """

  alias Backup.{Scanner, RsyncWorker, Retry, Util}

  @batch_size 200

  def run(src, dst, workers, retries, opts) do
    with :ok <- Util.check(File.dir?(src), "Source directory missing", 2),
         :ok <- Util.check(File.dir?(dst), "Destination missing", 3),
         {:ok, started} <- start_workers(src, dst, workers, opts) do
      {batch_count, file_count, failures} = stream_batches(src, started, retries)

      # Finish workers and collect each real rsync exit code.
      results = Enum.map(started, &RsyncWorker.finish/1)
      codes = Enum.zip_with(results, 1..length(results), &{&1, &2})

      print_summary(batch_count, file_count)

      case failures do
        [] ->
          if Enum.all?(results, &match?({:ok, 0}, &1)) do
            Util.success("all sync jobs finished")
          else
            report_nonzero_exits(codes)
            System.halt(4)
          end

        failed ->
          Util.error("#{length(failed)} of #{batch_count} batches failed")
          System.halt(5)
      end
    else
      {:error, msg, code} ->
        Util.error(msg)
        System.halt(code)

      {:error, msg} ->
        Util.error(msg)
        System.halt(6)
    end
  end

  defp start_workers(src, dst, workers, opts) do
    started =
      Enum.reduce_while(1..workers, [], fn _, acc ->
        case RsyncWorker.start(src, dst, opts) do
          {:ok, worker} -> {:cont, [worker | acc]}
          {:error, msg} -> {:halt, {:error, msg}}
        end
      end)

    case started do
      {:error, _} = error -> error
      workers -> {:ok, Enum.reverse(workers)}
    end
  end

  defp stream_batches(src, workers, retries) do
    total_files = count_files(src)

    if total_files == 0 do
      Util.warn("no regular files found under #{src}")
      {0, 0, []}
    else
      Util.info("Found #{total_files} files; syncing with #{length(workers)} workers...")

      {batch_count, sent, failures} =
        Scanner.scan(src)
        |> Stream.chunk_every(@batch_size)
        |> Enum.reduce({0, 0, []}, fn batch, {n, sent, failures} ->
          worker = Enum.at(workers, rem(n, length(workers)))

          result =
            Retry.attempt(fn -> RsyncWorker.send_batch(worker, batch) end, retries)

          sent = sent + length(batch)
          report_progress(sent, total_files)

          case result do
            :ok ->
              {n + 1, sent, failures}

            {:error, _reason} ->
              {n + 1, sent, [{n + 1, length(batch)} | failures]}
          end
        end)

      IO.puts("")
      {batch_count, sent, Enum.reverse(failures)}
    end
  end

  defp count_files(src), do: src |> Scanner.scan() |> Enum.count()

  defp report_progress(sent, total) do
    percent = if total > 0, do: Float.round(sent / total * 100, 1), else: 0.0
    IO.write("\r#{sent}/#{total} files (#{percent}%)")
  end

  defp print_summary(batch_count, file_count) do
    Util.info("Sent #{file_count} files in #{batch_count} batches")
  end

  defp report_nonzero_exits(codes) do
    for {{:ok, code}, idx} <- codes, code != 0 do
      Util.error("rsync worker #{idx} exited with code #{code}")
    end
  end
end