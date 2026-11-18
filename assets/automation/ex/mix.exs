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
    [{:playwright, github: "ftes/playwright_ex", ref: "5fe2de9880c7b7b7b53c947e4ed18ca21d3512cc"}]
  end
end
