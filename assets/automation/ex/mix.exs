defmodule OliE2E.MixProject do
  use Mix.Project

  def project do
    [
      app: :oli_e2e,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["test/support"],
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [{:playwright, "~> 1.65.0-rc.2", hex: :playwright_ex}]
  end
end
