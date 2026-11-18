defmodule OliE2E.Pom.PublishProject do
  @moduledoc "Port of src/systems/torus/pom/project/PublishProjectPO.ts."

  alias OliE2E.Waiter
  alias Playwright.{Locator, Page}

  defstruct [:page, :publish_button, :ok_button, :auto_push_checkbox, :description_textarea]

  def new(page) do
    %__MODULE__{
      page: page,
      publish_button: Page.locator(page, "#button-publish"),
      ok_button: Page.get_by_role(page, :button, name: "Ok"),
      auto_push_checkbox: Page.locator(page, "#publication_auto_push_update"),
      description_textarea: Page.locator(page, "#publication_description")
    }
  end

  def click_publish(po), do: Locator.click!(po.publish_button)

  def click_ok(po) do
    Waiter.wait_for_load_state(po.page)
    Locator.click!(po.ok_button)
  end

  def click_auto_push(po), do: Locator.click!(po.auto_push_checkbox)

  @doc "`true`/`false`, or `nil` (JS null) when the checkbox is not visible."
  def auto_push_is_checked(po) do
    if Locator.is_visible!(po.auto_push_checkbox) do
      Locator.is_checked!(po.auto_push_checkbox)
    else
      nil
    end
  end

  def fill_description(po, description), do: Locator.fill!(po.description_textarea, description)
end
