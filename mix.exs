defmodule Sencha.MixProject do
  use Mix.Project

  def project do
    [
      app: :sencha,
      version: "0.3.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Sencha.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      # Store client credentials persistently
      {:ecto, "~> 3.13"},

      # PostgreSQL database client (SQLite can not store the arrays that we need)
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"}
    ]
  end
end
