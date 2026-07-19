defmodule ScannerTest do
  use ExUnit.Case
  alias Backup.Scanner

  setup do
    root = Briefly.create!(directory: true)
    %{root: root}
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
