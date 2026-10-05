defmodule Snapshot.MixProject do
  use Mix.Project

  def project do
    [
      app: :snapshot,
      version: "0.1.0",
      elixir: "~> 1.19",
      escript: [main_module: Snapshot.CLI],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def cli do
    [
      default_task: "escript.build",
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:briefly, "~> 0.5.1", only: :test, runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
