defmodule Backup.Scanner do
  def scan(dir) do
    Stream.resource(
      fn -> [dir] end,
      fn
        [] ->
          {:halt, []}

        [path | rest] ->
          cond do
            File.dir?(path) ->
              {:ok, items} = File.ls(path)
              children = Enum.map(items, &Path.join(path, &1))
              {[], children ++ rest}

            File.regular?(path) ->
              {[path], rest}

            true ->
              {[], rest}
          end
      end,
      fn _ -> :ok end
    )
  end
end
