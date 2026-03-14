
defmodule Backup.Rsync do
  alias Backup.Util

  def sync_batch(files, src, dst, opts) do
    exe = System.find_executable("rsync")

    if exe == nil do
      raise "rsync not found in PATH"
    end

    tmp = Path.join(System.tmp_dir!(), "rsync_batch_#{:erlang.unique_integer()}")

    try do

      File.open!(tmp, [:write], fn f ->
        Enum.each(files, fn file ->
          IO.write(f, Path.relative_to(file, src))
          IO.write(f, "\n")
        end)
      end)

      args =
        flags(opts) ++
          ["--files-from=#{tmp}", src, dst]

      port =
        Port.open({:spawn_executable, exe}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          args: args,
        ])

      progress_loop(port, "")
    after
      File.rm(tmp)
    end
  end

  #do I need these they can cause lots of trouble
  #"--partial",
  #"--append-verify",
  def flags(opts) do
    base = [
      "-a",
      "--human-readable",
      "--info=progress2"
    ]

    base
    |> maybe("--dry-run", opts[:dry_run])
    |> maybe("--delete", opts[:delete])
  end

  defp maybe(list, _flag, nil), do: list
  defp maybe(list, flag, true), do: list ++ [flag]

  defp progress_loop(port, buffer) do
    receive do
      {^port, {:data, data}} ->
        text = buffer <> data
        parts = String.split(text, "\n")

        {lines, rest} =
          if String.ends_with?(text, "\n") do
            {parts, ""}
          else
            {Enum.drop(parts, -1), List.last(parts)}
          end

        Enum.each(lines, &handle_line/1)

        progress_loop(port, rest)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, code}} ->
        raise "rsync failed #{code}"
    after
      300_000 ->
        raise "rsync timeout"
    end
  end

  defp handle_line(line) do
    if String.contains?(line, "%") do
      Util.progress(line)
    end
  end
end
