defmodule OliE2E.Pom.AuthorDashboard do
  @moduledoc "Port of src/systems/torus/pom/dashboard/AuthorDashboardPO.ts (without the Table helpers, unused by the @pr specs)."

  alias OliE2E.{Utils, Verifier}
  alias Playwright.{Locator, Page}

  defstruct [
    :page,
    :utils,
    :search_input,
    :new_project_button,
    :project_name_input,
    :create_button,
    :title_header
  ]

  def new(page) do
    %__MODULE__{
      page: page,
      utils: Utils.new(page),
      search_input: Page.locator(page, "#text-search-input"),
      new_project_button: Page.locator(page, "#button-new-project"),
      project_name_input: Page.locator(page, "#project_title"),
      title_header: Page.get_by_role(page, :cell, name: "Title", exact: true),
      create_button: Page.get_by_role(page, :button, name: "Create")
    }
  end

  def click_project_link(%{page: page}, project_name) do
    project_link = Page.get_by_role(page, :link, name: project_name)
    Locator.click!(project_link)
  end

  def sort_by_title_descending(po) do
    if Locator.is_visible!(po.title_header) do
      Locator.click!(po.title_header)
      Utils.sleep(Utils.new(po.page), 2)
    end
  end

  def search_project(po, name) do
    Utils.write_with_delay(po.utils, po.search_input, name)
    Verifier.expect_not_contain_class(po.search_input, "phx-hook-loading")
  end

  def click_new_project_button(po) do
    Utils.force_click(po.utils, po.new_project_button, po.project_name_input)
  end

  def fill_project_name(po, name) do
    Locator.click!(po.project_name_input)
    Locator.fill!(po.project_name_input, name)
  end

  def click_create_button(po), do: Locator.click!(po.create_button)
end
