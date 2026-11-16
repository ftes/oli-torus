defmodule OliE2E.Waiter do
  @moduledoc "Port of src/core/wait/Waiter.ts."

  alias Playwright.{Locator, Page}

  @doc """
  Waits for the page to reach a specific load state.
  - `:load`: waits for the `load` event to be fired.
  - `:domcontentloaded`: waits for the `DOMContentLoaded` event to be fired.
  - `:networkidle`: waits until there are no network connections for at least 500 ms.
  """
  def wait_for_load_state(page, state \\ :domcontentloaded) do
    Page.wait_for_load_state!(page, state)
  end

  @doc "`state` is `:attached`, `:detached`, `:visible` or `:hidden`."
  def wait_for(locator, state, timeout \\ 5000) do
    Locator.wait_for!(locator, state: state, timeout: timeout)
  end
end
