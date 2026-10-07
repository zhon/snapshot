defmodule Snapshot.Runner do
  @moduledoc """
  Scans a source tree and distributes batches across persistent rsync workers.

  Progress is reported per *file*, and a failure in any batch fails the whole
  run with a non-zero exit code. A snapshot that reports success while silently
  dropping files is worse than one that fails loudly.
  """

  alias Snapshot.{Sweep, Scanner, RsyncWorker, Retry, Util}

  @batch_size 200
  @type opts :: [workers: pos_integer() | nil, retries: non_neg_integer() | nil, dry_run: boolean() | nil, delete: boolean() | nil, exclude: [String.t()] | nil, flags: String.t() | [String.t()] | nil, rsync_path: String.t() | nil]

  @spec run(String.t(), String.t(), pos_integer(), non_neg_integer(), opts()) :: no_return()
  def run(src, dst, workers, retries, opts) do
    with :ok <- Util.check(File.dir?(src), "Source directory missing", 2),
         :ok <- Util.check(File.dir?(dst), "Destination missing", 3),
         {:ok, started} <- start_workers(src, dst, workers, opts) do
      {batch_count, file_count, failures} = stream_batches(src, started, retries)

      # Finish workers and collect each real rsync exit code.
      results = Enum.map(started, &RsyncWorker.finish/1)
      codes = Enum.zip_with(results, 1..length(results), &{&1, &2})

      print_summary(batch_count, file_count)

      # Sweeping is opt-in. It only runs after a fully successful sync --
      # deleting after a partial or failed transfer would remove destination
      # entries whose source copies never arrived.
      if Util.truthy(opts[:delete]) and failures == [] and Enum.all?(results, &match?({:ok, 0}, &1)) do
        sweep(src, dst, opts)
      end

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

  # A failed sweep is not a failed run: the sync itself succeeded and every
  # file is at the destination. The only thing not done is the cleanup, so this
  # warns rather than halting with a non-zero code.
  defp sweep(src, dst, opts) do
    Util.info("Sweeping destination entries that are no longer in the source...")
    dry_run? = Util.truthy(opts[:dry_run])

    case Sweep.sweep(src, dst,
           rsync_path: opts[:rsync_path],
           dry_run: dry_run?,
           exclude: opts[:exclude]
         ) do
      {:ok, []} ->
        Util.info("Sweep: nothing to delete")

      {:ok, paths} ->
        if dry_run? do
          Util.info("Sweep: would delete #{length(paths)} entries (dry run)")
        else
          Util.info("Sweep: deleted #{length(paths)} entries")
        end

      {:error, reason, _code} ->
        Util.warn("Sweep skipped (#{inspect(reason)}); destination left as-is")
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
    # Scan once and collect to list so we know the total without a separate
    # pass. The list is held in memory for the duration of the sync.
    all_files = Enum.to_list(Scanner.scan(src))
    total_files = length(all_files)

    if total_files == 0 do
      Util.warn("no regular files found under #{src}")
      {0, 0, []}
    else
      # Report progress as we scan, since scanning is the slowest part.
      Util.info("Scanning #{src} for files...")
      total_batches = ceil(total_files / @batch_size)
      Util.info("Found #{total_files} files; syncing with #{length(workers)} workers...")

      {batch_count, sent, failures} =
        all_files
        |> Stream.chunk_every(@batch_size)
        |> Enum.reduce({0, 0, []}, fn batch, {n, sent, failures} ->
          worker = Enum.at(workers, rem(n, length(workers)))

          result =
            Retry.attempt(fn -> RsyncWorker.send_batch(worker, batch) end, retries)

          sent = sent + length(batch)
          report_progress(n + 1, total_batches, sent, total_files)

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

  defp report_progress(batch_idx, total_batches, sent, total_files) do
    percent = if total_files > 0, do: Float.round(sent / total_files * 100, 1), else: 0.0
    IO.write("\rBatch #{batch_idx}/#{total_batches} | #{sent}/#{total_files} files (#{percent}%)")
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