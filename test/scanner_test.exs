defmodule ScannerTest do
  use ExUnit.Case
  alias Backup.Scanner

  setup do
    root = Briefly.create!(directory: true)
    %{root: root}
  end

  test "finds deeply nested movie" do
    root = Briefly.create!(directory: true)

    dir = Path.join(root, "2026/2026-07-12")
    File.mkdir_p!(dir)

    movie = Path.join(dir, "Timelapse2.mov")
    File.write!(movie, "contents")

    assert movie in Enum.to_list(Backup.Scanner.scan(root))
  end

  defp reference_scan(dir) do
    for entry <- File.ls!(dir),
      path = Path.join(dir, entry),
      reduce: [] do
        acc ->
        cond do
          File.regular?(path) ->
            [path | acc]

          File.dir?(path) ->
            reference_scan(path) ++ acc

          true ->
            acc
        end
      end
  end

  test "scanner matches reference implementation" do
    root = Briefly.create!(directory: true)

  # Build a representative directory tree here...
    dir = Path.join(root,
      "/Snapshot/2026/2026-06-29 - 07-03 Yellowstone Trip/2026-06-29"
    )
    File.mkdir_p!(dir)
    for i <- 1..500 do
      File.write!(Path.join(root, "file#{i}.txt"), "")
    end

    assert Enum.sort(Backup.Scanner.scan(root) |> Enum.to_list()) ==
      Enum.sort(reference_scan(root))

    files_sent =
      Scanner.scan(root)
      |> Stream.chunk_every(200)
      |> Enum.flat_map(fn batch ->
        batch
      end)

    assert Enum.sort(files_sent) ==
      Enum.sort(Scanner.scan(root) |> Enum.to_list())
  end

  test "finds files in a large directory" do
    root = Briefly.create!(directory: true)

    for i <- 1..500 do
      File.write!(Path.join(root, "file#{i}.txt"), "")
    end

    files = Enum.to_list(Backup.Scanner.scan(root))

    assert length(files) == 500
  end

  test "finds every file in a mixed tree" do
    root = Briefly.create!(directory: true)

    expected =
      for d <- 1..10,
      f <- 1..20 do
        dir = Path.join(root, "dir#{d}")
        File.mkdir_p!(dir)

        file = Path.join(dir, "file#{f}.txt")
        File.write!(file, "")
        file
      end

    assert Enum.sort(expected) ==
      Enum.sort(Enum.to_list(Backup.Scanner.scan(root)))
  end

  test "returns an empty stream for an empty directory", %{root: root} do
    assert Enum.to_list(Scanner.scan(root)) == []
  end


  test "finds a single file", %{root: root} do
    file = Path.join(root, "hello.txt")
    File.write!(file, "hello")

    assert Enum.to_list(Scanner.scan(root)) == [file]
  end

  test "finds multiple files", %{root: root} do
    a = Path.join(root, "a.txt")
    b = Path.join(root, "b.txt")

    File.write!(a, "")
    File.write!(b, "")

    assert Enum.sort(Scanner.scan(root) |> Enum.to_list()) ==
      Enum.sort([a, b])
  end

  test "recursively scans subdirectories", %{root: root} do
    sub = Path.join(root, "sub")
    File.mkdir!(sub)

    root_file = Path.join(root, "root.txt")
    sub_file = Path.join(sub, "child.txt")

    File.write!(root_file, "")
    File.write!(sub_file, "")

    assert Enum.sort(Scanner.scan(root) |> Enum.to_list()) ==
      Enum.sort([root_file, sub_file])
  end

  test "ignores empty directories", %{root: root} do
    File.mkdir!(Path.join(root, "empty"))

    assert Enum.to_list(Scanner.scan(root)) == []
  end

  test "descends into nested directories", %{root: root} do
    deep = Path.join(root, "a/b/c")
    File.mkdir_p!(deep)

    file = Path.join(deep, "deep.txt")
    File.write!(file, "")

    assert Enum.to_list(Scanner.scan(root)) == [file]
  end

  test "does not return directory names", %{root: root} do
    dir = Path.join(root, "dir")
    File.mkdir!(dir)

    file = Path.join(dir, "file.txt")
    File.write!(file, "")

    paths = Enum.to_list(Scanner.scan(root))

    refute dir in paths
    assert file in paths
  end

  test "returns no files when the root directory is empty", %{root: root} do
    assert Scanner.scan(root) |> Enum.count() == 0
  end

end
