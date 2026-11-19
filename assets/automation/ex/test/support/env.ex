defmodule OliE2E.Env do
  @moduledoc "Runtime configuration (src/core/runtimeConfig.ts): base URL and tokens from the environment."

  def base_url, do: get("PLAYWRIGHT_BASE_URL") || "http://localhost"
  def scenario_token, do: get("PLAYWRIGHT_SCENARIO_TOKEN") || "my-token"
  def captcha_token, do: System.get_env("PLAYWRIGHT_CAPTCHA_TOKEN")
  def automation_api_key, do: System.get_env("PLAYWRIGHT_AUTOMATION_API_KEY")

  # An empty variable counts as unset, as JS's `process.env.X || default`.
  defp get(name), do: if(System.get_env(name) not in [nil, ""], do: System.get_env(name))
end
