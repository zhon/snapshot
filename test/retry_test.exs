defmodule RetryTest do
  use ExUnit.Case
  alias Backup.Retry

  test "retries until success" do
    pid = self()

    fun = fn ->
      send(pid, :called)
      raise "fail"
    end

    Retry.attempt(fun, 1)

    assert_received :called
  end
end
