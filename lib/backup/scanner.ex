defmodule Backup.Scanner do
  def scan(root) do
    Stream.resource(
      fn -> init(root) end,
      &step/1,
      fn _ -> :ok end
    )
  end

  defp init(root) do
    case File.ls(root) do
      {:ok, entries} ->
        [{root, entries}]

      _ ->
        []
    end
  end

  defp step([]) do
    {:halt, []}
  end

  defp step([{_dir, []} | rest]) do
    step(rest)
  end

  defp step([{dir, [name | remaining]} | rest]) do
    path = dir <> "/" <> name

    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        new_stack =
          case File.ls(path) do
            {:ok, children} ->
              [{path, children}, {dir, remaining} | rest]

            _ ->
              [{dir, remaining} | rest]
          end

        {[], new_stack}

      {:ok, %File.Stat{type: :regular}} ->
        {[path], [{dir, remaining} | rest]}

      _ ->
        {[], [{dir, remaining} | rest]}
    end
  end
end
