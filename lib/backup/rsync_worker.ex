defmodule Backup.RsyncWorker do
  alias Backup.Util

  # Start persistent rsync worker
  def start(src, dst, opts) do
    exe = System.find_executable("rsync") || raise "rsync not found in PATH"

    args =
      Backup.Rsync.flags(opts) ++
        ["--files-from=-", "--from0", src, dst]

    Port.open({:spawn_executable, exe}, [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      :eof,
      args: args
    ])
  end

  # Spawn listener for live rsync output
  def listen(port) do
    spawn(fn -> loop(port, "") end)
  end

  defp loop(port, buffer) do
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

        Enum.each(lines, &Util.progress/1)
        loop(port, rest)

      {^port, {:exit_status, code}} ->
        if code != 0, do: IO.puts("rsync exited with code #{code}")
    after
      300_000 ->
        IO.puts("rsync timeout")
    end
  end

  # Send a batch of files (NUL-separated)
  def send_batch(port, files, src) do
    # Only send regular files
    files =
      Enum.filter(files, &File.regular?/1)

    if files != [] do
      data = Enum.map_join(files, <<0>>, &Path.relative_to(&1, src)) <> <<0>>
      Port.command(port, data)
    end
  end

  # Finish worker
  def finish(port) do
    Port.command(port, "")  # signal EOF
    Port.close(port)
  end
end
