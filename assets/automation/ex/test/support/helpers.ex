defmodule OliE2E.Helpers do
  @moduledoc "Small stand-ins for JS idioms the client has no equivalent of."

  require Playwright.Test

  @doc """
  A run id for scenario seeds (`-${Date.now()}-${process.pid}` in JS). The modules share
  one OS pid, so a number unique in the VM is added. It goes first because Torus
  slugifies only a title's first 30 characters: project slugs then differ too.
  """
  def run_id do
    unique =
      System.unique_integer([:positive])
      |> rem(1000)
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    random = :rand.uniform(10_000) |> Integer.to_string() |> String.pad_leading(5, "0")
    "-#{unique}#{random}-#{System.os_time(:millisecond)}-#{System.pid()}"
  end

  @doc """
  The JS `@step` decorator (src/core/decoration/step.ts): `Playwright.Test.step/2`.

  Workaround: playwright_ex's `step` raises outside a test, in `setup_all`, where JS's
  `test.step` works in a `beforeAll` hook too. There the body runs without a step.
  """
  defmacro step(title, do: block) do
    quote do
      OliE2E.Helpers.run_step(unquote(title), fn -> unquote(block) end)
    end
  end

  @doc false
  def run_step(title, body) do
    Playwright.Test.step(title, body)
  rescue
    error in RuntimeError ->
      if error.message == "test.step() can only be called from a test",
        do: body.(),
        else: reraise(error, __STACKTRACE__)
  end
end
