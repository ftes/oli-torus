defmodule OliE2E.Pom.BasicPracticePage do
  @moduledoc """
  Port of src/systems/torus/pom/page/BasicPracticePagePO.ts. Only the methods that
  CurriculumTask, SimpleAuthorPO and AdvancedAuthorPO use are ported (the paragraph/insert/preview
  helpers and the MCQ-branching-lesson builder are not).
  """

  alias OliE2E.{Utils, Verifier, Waiter}
  alias Playwright.{Expect, Locator, Page}

  defstruct [
    :page,
    :page_title,
    :changes_saved,
    :changes_saving,
    :edit_title_button,
    :page_title_input,
    :page_title_save_button,
    :adaptive_read_only_input,
    :adaptive_author_toolbar,
    :advanced_author_flowchart_mode,
    :utils
  ]

  @janus_mcq_defined "() => customElements.get('janus-mcq') != null"

  def new(page) do
    %__MODULE__{
      page: page,
      page_title:
        page
        |> Page.locator("div.TitleBar h1, #page_editor-container div.TitleBar span")
        |> Locator.first(),
      changes_saved: Page.get_by_text(page, "All changes saved"),
      changes_saving: Page.get_by_text(page, "Saving..."),
      edit_title_button:
        page
        |> Page.locator("div.TitleBar")
        |> Locator.get_by_role(:button, name: "Edit Title")
        |> Locator.first(),
      page_title_input: page |> Page.locator("div.TitleBar #page_title_input") |> Locator.first(),
      page_title_save_button:
        page
        |> Page.locator("div.TitleBar")
        |> Locator.get_by_role(:button, name: "Save")
        |> Locator.first(),
      adaptive_read_only_input:
        Page.locator(page, ~s|#adaptive_read_only_toggle input[name="adaptive_read_only"]|),
      adaptive_author_toolbar:
        Page.locator(
          page,
          Enum.join(
            [
              "#advanced-authoring nav.aa-header-nav",
              "#advanced-authoring .component-toolbar",
              "#advanced-authoring .top-toolbar",
              "#advanced-authoring .sidebar-header",
              ".flowchart-editor .top-toolbar",
              ".flowchart-editor .sidebar-header"
            ],
            ", "
          )
        ),
      advanced_author_flowchart_mode:
        page
        |> Page.locator("#advanced-authoring .sidebar-header, .flowchart-editor .sidebar-header")
        |> Locator.filter(has_text: "Flowchart")
        |> Locator.first(),
      utils: Utils.new(page)
    }
  end

  def verify_title_page(po, title_page \\ "New Page"),
    do: Verifier.expect_has_text(po.page_title, title_page)

  def ensure_advanced_author_editable(po) do
    disable_adaptive_read_only(po)
    assert_advanced_author_editable(po)
  end

  def ensure_simple_author_ready(po) do
    complete_simple_author_onboarding_if_present(po)
    disable_adaptive_read_only(po)

    po.adaptive_author_toolbar
    |> Locator.first()
    |> Locator.wait_for!(state: :visible, timeout: 30_000)

    # 'Simple Author flowchart mode should load.'
    Expect.to_be_visible!(po.advanced_author_flowchart_mode, timeout: 30_000)
    Page.wait_for_function!(po.page, @janus_mcq_defined, nil, timeout: 30_000)
  end

  @doc "Switches a reopened adaptive lesson out of read-only mode when it loads locked."
  def disable_adaptive_read_only(po) do
    has_toggle = count(po.adaptive_read_only_input) > 0

    if has_toggle do
      # The toggle reflects the lock state only once it is enabled.
      Expect.to_be_enabled!(po.adaptive_read_only_input, timeout: 30_000)

      if checked?(po.adaptive_read_only_input) do
        Page.evaluate!(po.page, """
        () => {
          const input = document.querySelector('input[name="adaptive_read_only"]');

          if (input?.checked) {
            input.click();
          }
        }
        """)

        Expect.not_to_be_checked!(po.adaptive_read_only_input, timeout: 10_000)
      end
    end

    :ok
  end

  defp assert_advanced_author_editable(po) do
    # 'Advanced authoring should be editable.'
    Expect.to_be_enabled!(po.edit_title_button, timeout: 15_000)

    po.adaptive_author_toolbar
    |> Locator.first()
    |> Locator.wait_for!(state: :visible, timeout: 30_000)
  end

  def wait_for_advanced_author_flowchart_ready(po) do
    complete_simple_author_onboarding_if_present(po)

    # 'Simple Author flowchart mode should load.'
    Expect.to_be_visible!(po.advanced_author_flowchart_mode, timeout: 30_000)
    Locator.click!(po.advanced_author_flowchart_mode)

    po.page
    |> Page.locator(".flowchart-node")
    |> Locator.first()
    |> Locator.wait_for!(state: :visible, timeout: 30_000)

    Expect.to_be_visible!(flowchart_screen_title(po, "Welcome Screen"), timeout: 30_000)
    Expect.to_be_visible!(flowchart_screen_title(po, "End of Lesson"), timeout: 30_000)
  end

  defp complete_simple_author_onboarding_if_present(po) do
    wizard = Page.locator(po.page, ".onboard-wizard")

    wizard_visible = Locator.wait_for(wizard, state: :visible, timeout: 3000) == :ok

    if wizard_visible do
      for _step_index <- 0..2 do
        next_button = wizard |> Locator.get_by_role(:button, name: ~r/^Next$/) |> Locator.last()
        Expect.to_be_enabled!(next_button, timeout: 10_000)
        Locator.click!(next_button)
      end
    end

    :ok
  end

  defp flowchart_screen_title(po, title) do
    po.page
    |> Page.locator(".flowchart-node .title-text")
    |> Locator.filter(has_text: Regex.compile!("^#{escape_reg_exp(title)}$"))
    |> Locator.first()
  end

  defp escape_reg_exp(value), do: Regex.replace(~r/[.*+?^${}()|\[\]\\]/, value, "\\\\\\0")

  def rename_title(po, title_page) do
    Verifier.expect_is_visible(po.edit_title_button)
    ensure_title_editing_enabled(po)
    Locator.click!(po.edit_title_button)
    Waiter.wait_for(po.page_title_input, :visible)
    Locator.fill!(po.page_title_input, title_page)
    Locator.click!(po.page_title_save_button)
    Waiter.wait_for(po.page_title_input, :hidden, 10_000)
    verify_title_page(po, title_page)
  end

  defp ensure_title_editing_enabled(po) do
    unless match?({:ok, true}, Locator.is_enabled(po.edit_title_button)) do
      ensure_advanced_author_editable(po)

      # 'Page title edit button should be enabled.'
      Expect.to_be_enabled!(po.edit_title_button, timeout: 15_000)
    end
  end

  def wait_for_changes_saved(po) do
    if match?({:ok, true}, Locator.is_visible(po.changes_saving)) do
      Waiter.wait_for(po.changes_saving, :hidden, 15_000)
    end

    # 'The "All changes saved" notification message does not appear.'
    Verifier.expect_is_visible(po.changes_saved)
    Utils.paint_element(po.utils, po.changes_saved)
  end

  def flush_pending_page_changes(po) do
    Page.wait_for_timeout!(po.page, 100)

    Page.evaluate!(po.page, """
    () => {
      window.dispatchEvent(new CustomEvent('phx:authoring_flush_page_editor_requested'));
    }
    """)

    wait_for_changes_saved(po)
  end

  defp count(locator) do
    case Locator.count(locator) do
      {:ok, n} -> n
      _ -> 0
    end
  end

  defp checked?(locator), do: match?({:ok, true}, Locator.is_checked(locator))
end
