defmodule OliE2E.Helpers do
  @moduledoc "Small stand-ins for JS idioms the client has no equivalent of."

  alias Playwright.Promise

  @doc "`await Promise.all([...])` of zero-arity functions (each starts its own wait)."
  def promise_all(funs) do
    funs |> Enum.map(&Promise.async/1) |> Enum.map(&Promise.await!/1)
  end
end
