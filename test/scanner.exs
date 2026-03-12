defmodule ScannerTest do
  use ExUnit.Case
  alias Backup.Scanner

  test "scans files" do
    File.mkdir_p!("tmp/a")
    File.write!("tmp/a/file.txt", "hi")

    files =
      "tmp"
      |> Scanner.scan()
      |> Enum.to_list()

    assert Enum.any?(files, &String.contains?(&1, "file.txt"))
  end

  test 'weird' do

    fail
  end
end
