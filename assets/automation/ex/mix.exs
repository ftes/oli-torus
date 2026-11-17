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
    [{:playwright, github: "ftes/playwright_ex", ref: "0217c3445a6845750cdd2a9ce0355588b0147356"}]
  end
end
