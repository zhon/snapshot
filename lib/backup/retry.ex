defmodule Backup.Retry do
  alias Backup.Util

  def attempt(fun, retries) do
    try do
      fun.()
    rescue
      e ->
        if retries > 0 do
          Util.warn("retrying job: #{Exception.message(e)}")
          attempt(fun, retries - 1)
        else
          Util.error("job failed after retries")
        end
    end
  end
end
