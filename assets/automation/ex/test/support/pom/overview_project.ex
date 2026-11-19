defmodule OliE2E.Pom.OverviewProject do
  @moduledoc """
  Port of src/systems/torus/pom/project/OverviewProjectPO.ts. Only `details` (a getter
  returning an object of methods in JS: here `get_project_id/1` and `wait_for_editor_ready/1`)
  is ported; advancedActivities, publishingVisibility and projectAttributes are unused by the @pr specs.
  """

  alias OliE2E.Verifier
  alias Playwright.{Locator, Page}

  defstruct [:page, :project_id_input, :toolbar]

  def new(page) do
    %__MODULE__{
      page: page,
      project_id_input: Page.locator(page, "#project_slug"),
      toolbar: Page.locator(page, ".toolbar_nGbXING3")
    }
  end

  # details.getProjectID
  def get_project_id(po), do: Locator.input_value!(po.project_id_input)

  # details.waitForEditorReady
  def wait_for_editor_ready(po), do: Verifier.expect_is_visible(po.toolbar)
end
