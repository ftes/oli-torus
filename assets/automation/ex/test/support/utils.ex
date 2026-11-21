defmodule OliE2E.Utils do
  @moduledoc "Port of src/core/Utils.ts (only the methods the @pr specs use)."

  alias OliE2E.{Verifier, Waiter}
  alias Playwright.{Locator, Page}

  defstruct [:page]

  def new(page \\ nil), do: %__MODULE__{page: page}

  def force_click(
        %{page: page},
        element_to_click,
        element_to_validate,
        max_attempts \\ 5,
        wait_ms \\ 200
      ) do
    Enum.reduce_while(0..(max_attempts - 1)//1, nil, fn i, _ ->
      Locator.click!(element_to_click, force: true)

      try do
        Verifier.expect_is_visible(element_to_validate, "Force click didn't work")
        {:halt, :ok}
      rescue
        _ ->
          if i == max_attempts - 1 do
            raise "forceClick failed after #{max_attempts} attempts"
          end

          if page, do: Page.wait_for_timeout!(page, wait_ms)
          {:cont, nil}
      end
    end)
  end

  def paint_element(_utils, locator) do
    Locator.evaluate!(locator, """
    (lo) => {
      lo.style.outline = '3px solid red';
      lo.style.backgroundColor = 'yellow';
    }
    """)
  end

  def sleep(_utils, seconds \\ 1), do: Process.sleep(round(seconds * 1000))

  def write_with_delay(_utils, search_input, text, delay \\ 100) do
    Locator.press_sequentially!(search_input, text, delay: delay)
  end

  def modal_disappears(%{page: page}) do
    modal_class = ".modal-backdrop.fade.show"
    modal_backdrop = Page.locator(page, modal_class)

    try do
      Waiter.wait_for(modal_backdrop, :hidden)
    rescue
      _ ->
        # JS also logs the reload (`console.log`).
        Page.reload!(page)
    end
  end
end
