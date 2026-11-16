defmodule OliE2E.Scenario do
  @moduledoc "Port of src/core/seedScenario.ts: seed data through the /test/scenario-yaml endpoint."

  alias Playwright.APIRequestContext
  alias Playwright.APIResponse

  @endpoint "/test/scenario-yaml"

  @doc "Returns the decoded response (`%{\"ok\" => true, \"outputs\" => ...}`) or raises."
  def seed_from_file(request, scenario_file_path, params \\ %{}, base_url, token) do
    yaml = File.read!(Path.expand(scenario_file_path))
    target_url = base_url |> URI.merge(@endpoint) |> to_string()

    # The JS suite seeds one scenario per worker at a time. Concurrent seeds of
    # same-named scenarios race on the app's slug uniqueness (422 on
    # index_slug_sections), so seeds in this VM take turns.
    response =
      :global.trans({:oli_e2e_seed, :lock}, fn ->
        APIRequestContext.post!(request, target_url,
          headers: %{"x-playwright-scenario-token" => token, "content-type" => "application/json"},
          data: %{yaml: yaml, params: params}
        )
      end)

    unless APIResponse.ok(response) do
      raise "Scenario seed request failed (#{APIResponse.status(response)}): #{APIResponse.text!(response)}"
    end

    payload = APIResponse.json!(response)

    unless payload["ok"] do
      raise "Scenario seed execution failed: #{inspect(payload)}"
    end

    payload
  end
end
