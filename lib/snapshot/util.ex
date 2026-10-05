defmodule Snapshot.Util do
  @green IO.ANSI.green()
  @red IO.ANSI.red()
  @yellow IO.ANSI.yellow()
  @reset IO.ANSI.reset()

  def info(msg), do: IO.puts("#{@green}#{msg}#{@reset}")
  def success(msg), do: IO.puts("#{@green}#{msg}#{@reset}")
  def warn(msg), do: IO.puts("#{@yellow}#{msg}#{@reset}")
  def error(msg), do: IO.puts(:stderr, "#{@red}#{msg}#{@reset}")

  def progress(line) do
    IO.write("\r#{@yellow}#{line}#{@reset}")
  end

  def check(true, _, _), do: :ok
  def check(false, msg, code), do: {:error, msg, code}

  @doc """
  Returns whether a value should be considered "set" (truthy).

  Any value other than false/nil counts as set, matching how rsync flags
  are only added when truthy. Centralizing this avoids the old `maybe/3`
  bug where a `false` could reach pattern matching and raise a
  FunctionClauseError.
  """
  @spec truthy(value :: any()) :: boolean()
  def truthy(false), do: false
  def truthy(nil), do: false
  def truthy(_), do: true
end