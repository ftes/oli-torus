defmodule OliE2E.Tasks.Curriculum do
  @moduledoc """
  Port of src/systems/torus/tasks/CurriculumTask.ts: the page creation workflows the @pr
  specs use. Page types are the JS strings (`"basic-practice"`, `"basic-scored"`,
  `"adaptive-practice"`, `"adaptive-simple-practice"`); `"unit"` and `"module"` are not ported.
  `index` is `:first`, `:last` or an integer.
  """

  require Playwright.Test

  alias OliE2E.Pom.{BasicPracticePage, Curriculum}
  alias Playwright.Page

  defstruct [:page, :basic_pp, :curriculum]

  def new(page) do
    %__MODULE__{
      page: page,
      basic_pp: BasicPracticePage.new(page),
      curriculum: Curriculum.new(page)
    }
  end

  def add_page_and_enter(po, type, name_page \\ "New Page", link \\ "Edit Page", index \\ :last) do
    Playwright.Test.step "Add a page and enter. Type: #{type}" do
      add_page(po, type, true)
      enter_page(po, type, name_page, link, index)

      if type == "basic-practice" do
        BasicPracticePage.verify_title_page(po.basic_pp, name_page)
      end
    end
  end

  def add_page(po, type, stay_in_editor \\ false) do
    Playwright.Test.step "Add a page to the project. Type: #{type}" do
      opened_editor =
        case type do
          "basic-practice" ->
            Curriculum.click_basic_practice_button(po.curriculum)

          "basic-scored" ->
            Curriculum.click_basic_scored_button(po.curriculum)

          "adaptive-practice" ->
            Curriculum.click_adaptive_practice_button(po.curriculum)

          "adaptive-simple-practice" ->
            Curriculum.click_adaptive_simple_practice_button(po.curriculum)
        end

      if opened_editor and not stay_in_editor do
        return_to_curriculum(po)
      end

      opened_editor
    end
  end

  def add_page_with_title(po, type, title_page) do
    Playwright.Test.step "Add a page to the project. Type: #{type}, Title: #{title_page}" do
      add_page(po, type, true)
      enter_page(po, type, default_page_name(type), "Edit Page", :last)
      BasicPracticePage.rename_title(po.basic_pp, title_page)
      return_to_curriculum(po)
      Curriculum.expect_page_visible(po.curriculum, title_page)
    end
  end

  def create_adaptive_page_in_advanced_author(po, stay_in_editor \\ false, lesson_title \\ nil) do
    Playwright.Test.step "Create an adaptive page in Advanced Author" do
      opened_editor = add_page(po, "adaptive-practice", true)

      unless opened_editor do
        enter_page(
          po,
          "adaptive-practice",
          default_page_name("adaptive-practice"),
          "Edit Page",
          :last
        )
      end

      BasicPracticePage.ensure_advanced_author_editable(po.basic_pp)
      ignore_errors(fn -> BasicPracticePage.wait_for_changes_saved(po.basic_pp) end)
      if lesson_title, do: BasicPracticePage.rename_title(po.basic_pp, lesson_title)

      unless stay_in_editor do
        return_to_curriculum(po)
        Curriculum.expect_page_visible(po.curriculum, lesson_title || "New Advanced Author Page")
      end
    end
  end

  def create_adaptive_page_in_simple_author(po, stay_in_editor \\ false, lesson_title \\ nil) do
    Playwright.Test.step "Create an adaptive page in Simple Author" do
      opened_editor = add_page(po, "adaptive-simple-practice", true)

      unless opened_editor do
        enter_page(
          po,
          "adaptive-simple-practice",
          default_page_name("adaptive-simple-practice"),
          "Edit Page",
          :last
        )
      end

      BasicPracticePage.ensure_simple_author_ready(po.basic_pp)
      BasicPracticePage.wait_for_advanced_author_flowchart_ready(po.basic_pp)
      ignore_errors(fn -> BasicPracticePage.wait_for_changes_saved(po.basic_pp) end)
      if lesson_title, do: BasicPracticePage.rename_title(po.basic_pp, lesson_title)

      unless stay_in_editor do
        return_to_curriculum(po)
        Curriculum.expect_page_visible(po.curriculum, lesson_title || "New Simple Author Page")
      end
    end
  end

  def enter_page(po, type, name_page, link, index)
      when type in [
             "basic-practice",
             "basic-scored",
             "adaptive-practice",
             "adaptive-simple-practice"
           ] do
    Playwright.Test.step "Enter a page from the project. Type: #{type}" do
      unless Curriculum.page_editor_is_open(po.curriculum, 500) do
        Curriculum.click_edit_page_link(po.curriculum, name_page, link, index)
      end
    end
  end

  defp default_page_name("basic-practice"), do: "New Page"
  defp default_page_name("basic-scored"), do: "New Assessment"
  defp default_page_name("adaptive-practice"), do: "New Advanced Author Page"
  defp default_page_name("adaptive-simple-practice"), do: "New Simple Author Page"

  defp return_to_curriculum(po) do
    curriculum_url = String.replace(Page.url(po.page), ~r{/curriculum/[^/]+/edit$}, "/curriculum")
    Page.goto!(po.page, curriculum_url)
    Curriculum.waiting_to_be_centered(po.curriculum)
  end

  # `.catch(() => void 0)`
  defp ignore_errors(fun) do
    fun.()
  rescue
    _ -> :ok
  end
end
