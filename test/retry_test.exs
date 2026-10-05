defmodule RetryTest do
  use ExUnit.Case, async: true

  alias Snapshot.Retry

  test "returns the function's value on success" do
    assert Retry.attempt(fn -> :ok end, 2) == :ok
  end

  test "retries until success" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    result =
      Retry.attempt(
        fn ->
          Agent.update(counter, &(&1 + 1))

          if Agent.get(counter, & &1) < 3 do
            raise "fail"
          end

          :ok
        end,
        5
      )

    assert result == :ok
    assert Agent.get(counter, & &1) == 3
  end

  # Regression: the old implementation logged "job failed after retries" and
  # returned :ok, so the runner reported success after dropping files.
  test "returns an error tag when retries are exhausted" do
    assert {:error, %RuntimeError{message: "boom"}} =
             Retry.attempt(fn -> raise "boom" end, 0)
  end

  test "retries the configured number of times" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Retry.attempt(
      fn ->
        Agent.update(counter, &(&1 + 1))
        raise "always"
      end,
      2
    )

    assert Agent.get(counter, & &1) == 3
  end

  test "catches throws as well as raises" do
    assert {:error, {:throw, :nope}} = Retry.attempt(fn -> throw(:nope) end, 0)
  end

  test "does not retry when retries is zero" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Retry.attempt(
      fn ->
        Agent.update(counter, &(&1 + 1))
        raise "fail"
      end,
      0
    )

    assert Agent.get(counter, & &1) == 1
  end
end