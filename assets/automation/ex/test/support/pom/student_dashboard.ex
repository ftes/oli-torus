defmodule OliE2E.Pom.StudentDashboard do
  @moduledoc "Port of src/systems/torus/pom/dashboard/StudentDashboardPO.ts."

  alias OliE2E.Waiter
  alias Playwright.{Locator, Page}

  defstruct [:page, :search_input, :courses]

  def new(page) do
    %__MODULE__{
      page: page,
      search_input: Page.locator(page, "#section_search_input-input"),
      courses: page |> Page.locator("#content div > a") |> Locator.last()
    }
  end

  def wait_for_visible_courses(po), do: Waiter.wait_for(po.courses, :visible)

  def fill_search_input(po, text), do: Locator.fill!(po.search_input, text)

  def enter_course(%{page: page}, name) do
    course_card =
      page
      |> Page.locator("#content a")
      |> Locator.filter(has: Page.get_by_text(page, name, exact: true))
      |> Locator.first()

    Waiter.wait_for(course_card, :visible, 15_000)
    Locator.click!(course_card)
  end
end
