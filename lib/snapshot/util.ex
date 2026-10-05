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
end
