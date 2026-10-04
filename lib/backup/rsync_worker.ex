defmodule Backup.RsyncWorker do
  @moduledoc """
  A persistent rsync process fed NUL-separated file lists on stdin.

  Two Erlang details drive the design here:

    * Port messages are delivered to the process that *owns* the port (the one
      that called `Port.open/2`), not to a process spawned afterwards. So the
      output listener has to be started by `start/3` and handed the port via
      `:erlang.port_connect/2`, otherwise it never receives a single message.

    * `Port.close/1` signals EOF to rsync's stdin (verified: a full 3000-file
      transfer completes) but it also destroys the port, so no `exit_status`
      message can ever arrive. To still learn rsync's real exit code — 23 means
      a partial transfer, which a backup tool must not ignore — rsync runs
      under a tiny `sh -c` wrapper that records `$?` to a file we poll after
      closing stdin.
  """

  alias Backup.Util

  @doc """
  Starts one rsync worker. Returns `{:ok, worker}`.

  `worker` holds the port, the pid that receives its output, and the exit-code
  file the wrapper writes.
  """
  def start(src, dst, opts) do
    with {:ok, exe} <- Backup.Rsync.ensure_supported(opts[:rsync_path]),
         {:ok, tmp_dir} <- make_tmp_dir(),
         {:ok, code_file} <- make_code_file(tmp_dir) do
      args = Backup.Rsync.flags(opts) ++ ["--files-from=-", "--from0", src, dst]
      script = ~s("$1" "${@:2}"; echo $? > #{code_file})

      port =
        Port.open({:spawn_executable, "/bin/sh"}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          :eof,
          args: ["-c", script, "sh", exe | args]
        ])

      listener = start_listener(port)

      {:ok,
       %{
         port: port,
         listener: listener,
         code_file: code_file,
         tmp_dir: tmp_dir,
         src: src,
         alive?: true
       }}
    end
  end

  # Spawned by the port owner, then explicitly connected, so that rsync's
  # output is delivered here instead of filling the runner's mailbox.
  # A port that dies instantly (bad rsync path, immediate exec failure) is
  # already closed by the time we connect, so treat that as "nothing to do".
  defp start_listener(port) do
    spawn(fn ->
      # A port that dies instantly (bad rsync path, immediate exec failure) is
      # already closed by the time we connect; port_connect/2 raises in that
      # case rather than returning false.
      try do
        case :erlang.port_connect(port, self()) do
          true -> loop(port, "")
          _ -> :ok
        end
      rescue
        ArgumentError -> :ok
      end
    end)
  end

  defp loop(port, buffer) do
    receive do
      {^port, {:data, data}} ->
        {lines, rest} = split_lines(buffer <> data)
        Enum.each(lines, &Util.progress/1)
        loop(port, rest)

      {^port, {:exit_status, _code}} ->
        :ok

      {:stop, ^port} ->
        :ok
    end
  end

  defp split_lines(text) do
    parts = String.split(text, "\n")

    if String.ends_with?(text, "\n") do
      {parts, ""}
    else
      {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  @doc "Sends one batch of files (NUL-separated relative paths) to the worker."
  def send_batch(%{port: port, src: src, alive?: true}, files) do
    data = Enum.map_join(files, <<0>>, &Path.relative_to(&1, src)) <> <<0>>
    true = Port.command(port, data)
    :ok
  end

  @doc """
  Closes stdin so rsync finishes, and waits for its real exit code.

  Returns `{:ok, code}` or `{:error, reason}`. A non-zero code is returned, not
  raised — the caller decides how to report it.
  """
  def finish(%{port: port, code_file: code_file, tmp_dir: tmp_dir, listener: listener}) do
    send(listener, {:stop, port})
    # Clean EOF for stdin. This also invalidates the port, so exit_status is
    # deliberately not used here.
    Port.close(port)

    case await_exit_code(code_file) do
      {:ok, code} ->
        cleanup(tmp_dir)
        {:ok, code}

      {:error, reason} ->
        cleanup(tmp_dir)
        {:error, reason}
    end
  end

  defp await_exit_code(code_file, attempts \\ 240) do
    case File.read(code_file) do
      {:ok, contents} ->
        case Integer.parse(String.trim(contents)) do
          {code, _} -> {:ok, code}
          :error -> {:error, {:unparseable_exit_code, contents}}
        end

      {:error, :enoent} when attempts > 0 ->
        Process.sleep(250)
        await_exit_code(code_file, attempts - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup(tmp_dir), do: File.rm_rf(tmp_dir)

  defp make_tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "backup-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p(path)
    {:ok, path}
  end

  defp make_code_file(tmp_dir), do: {:ok, Path.join(tmp_dir, "exit_code")}
end