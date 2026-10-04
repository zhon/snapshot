defmodule Backup.Retry do
  @moduledoc """
  Runs a function, retrying on failure.

  A terminal failure returns `{:error, reason}` — it never reports success.
  Silently swallowing the error here previously made the runner print
  "all sync jobs finished" and exit 0 after dropping files.
  """

  alias Backup.Util

  @doc """
  Calls `fun`, retrying up to `retries` times.

  Returns whatever `fun` returns on success, or `{:error, exception}` once the
  retries are exhausted.
  """
  def attempt(fun, retries) when is_function(fun, 0) and is_integer(retries) and retries >= 0 do
    do_attempt(fun, retries)
  end

  defp do_attempt(fun, retries) do
    fun.()
  rescue
    e ->
      if retries > 0 do
        Util.warn("retrying job: #{Exception.message(e)}")
        do_attempt(fun, retries - 1)
      else
        Util.error("job failed after retries")
        {:error, e}
      end
  catch
    kind, reason ->
      if retries > 0 do
        Util.warn("retrying job: #{kind} #{inspect(reason)}")
        do_attempt(fun, retries - 1)
      else
        Util.error("job failed after retries")
        {:error, {kind, reason}}
      end
  end
end