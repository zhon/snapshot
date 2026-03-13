defmodule Backup.Scanner do
  def scan(root) do
    Stream.resource(
      fn -> [root] end,
      &step/1,
      fn _ -> :ok end
    )
  end

  defp step([]), do: {:halt, []}

  defp step([path | rest]) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        case File.ls(path) do
          {:ok, items} ->
            children =
              Enum.map(items, &Path.join(path, &1))

            {[], children ++ rest}

          {:error, _} ->
            {[], rest}
        end

      {:ok, %File.Stat{type: :regular}} ->
        {[path], rest}

      _ ->
        {[], rest}
    end
  end
end
