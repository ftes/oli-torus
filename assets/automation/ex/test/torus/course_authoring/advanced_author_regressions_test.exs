defmodule OliE2E.Torus.CourseAuthoring.AdvancedAuthorRegressionsTest do
  # Advanced Author known regressions @pr
  #
  # A test.describe.serial of three tests, the last two dependent: one test here, with a
  # step per JS test, so a rerun (`mix test --failed`) repeats all three, as a JS retry
  # repeats the serial group, and the describe's `let subscreenPartId` is a variable.
  # Own scenario seed and run id (the JS describe blocks share one); the JS `afterAll`
  # teardown only runs with PLAYWRIGHT_AUTOMATION_API_KEY (never in CI): omitted.
  use OliE2E.Case, async: true

  alias OliE2E.AdvancedAuthorSpec, as: Spec
  alias OliE2E.Pom.AdaptiveDeck
  alias OliE2E.Pom.AdvancedAuthor, as: Editor
  alias OliE2E.Tasks.{AdvancedAuthor, Home}

  @moduletag :pr

  @subscreen_lesson_title "Advanced Author Subscreen Layout"

  setup_all %{browser: browser} do
    run_id = Spec.run_id()
    section_slug = Spec.seed(browser, __DIR__, run_id)
    %{run_id: run_id, section_slug: section_slug}
  end

  # The three serial tests, each a step on a page of its own (`next_page/2`).
  @tag timeout: 150_000 + 180_000 + 120_000
  test "Advanced Author known regressions", %{
    browser: browser,
    page: page,
    run_id: run_id,
    section_slug: section_slug
  } do
    Test.step "item bank renders its default items and layout, and it persists after reload" do
      login_data = Spec.login_data(run_id)
      home_task = Home.new(page, login_data)
      task = AdvancedAuthor.new(page, login_data)
      editor = task.editor

      Home.login(home_task, :author)

      AdvancedAuthor.create_lesson(
        task,
        Spec.project_title(run_id),
        "Advanced Author Item Bank Layout"
      )

      item_bank_id = Editor.add_component(editor, :janus_item_bank)
      board = editor |> Editor.part(item_bank_id) |> Locator.locator(".grouping-author")

      board
      |> Locator.locator(".grouping-column-header")
      |> Expect.to_have_text!(["Item Bank", "Category 1", "Category 2"])

      board
      |> Locator.locator(".grouping-dropzone-bank .grouping-item")
      |> Expect.message("The two default items should start in the Item Bank column")
      |> Expect.to_have_count!(2)

      # Every new Advanced Author screen starts in Flow layout, so a new part's
      # width is already the responsive "100%" (`LayoutEditor.tsx`'s
      # `renderPart`) — Item Bank reflects that in its own internal layout
      # class (`grouping-util.ts`'s `isResponsiveGroupingLayout`), which is
      # distinct from the generic per-part `responsive-item` wrapper class
      # every other component gets (see "responsive layout arranges..." above).
      board
      |> Expect.message("Item Bank should render responsive by default")
      |> Expect.to_have_class!(~r/grouping--responsive/)

      AdvancedAuthor.reload_and_open_screen(task, "Welcome Screen")

      board
      |> Expect.message("The layout and default items should persist after reload")
      |> Expect.to_have_class!(~r/grouping--responsive/)

      board
      |> Locator.locator(".grouping-dropzone-bank .grouping-item")
      |> Expect.to_have_count!(2)
    end

    # "Responsive subscreens" (Raphael, Slack, 2026-10-12): there's no distinct
    # subscreen-specific responsive mechanism — it's the same per-part
    # `responsiveLayoutWidth` behavior already covered by "responsive layout
    # arranges..." above, just verified on a part that lives on a subscreen
    # nested under a Layer, including persistence and the delivered layout
    # classes (which that other test never checks — it only asserts the
    # authoring-side CSS class).
    page = OliE2E.Case.next_page(page, browser)

    subscreen_part_id =
      Test.step "author builds a responsive subscreen nested under a layer and publishes" do
        login_data = Spec.login_data(run_id)
        home_task = Home.new(page, login_data)
        task = AdvancedAuthor.new(page, login_data)
        editor = task.editor

        Home.login(home_task, :author)
        AdvancedAuthor.create_lesson(task, Spec.project_title(run_id), @subscreen_lesson_title)

        Editor.open_tab(editor, "Lesson")
        Editor.set_checkbox(editor, "Properties_responsiveLayout", true)

        AdvancedAuthor.add_layer(task, "Layer A")
        AdvancedAuthor.add_subscreen(task, "Layer A", "Layer A Subscreen")

        subscreen_part_id = Editor.add_component(editor, :janus_text_flow)
        Editor.set_text_flow_text(editor, subscreen_part_id, "Subscreen responsive text")
        Editor.set_part_width(editor, subscreen_part_id, "50% left")

        AdvancedAuthor.reload_and_open_screen(task, "Layer A Subscreen")

        editor
        |> Editor.responsive_item(subscreen_part_id)
        |> Expect.to_have_class!(~r/half-width/)

        editor
        |> Editor.responsive_item(subscreen_part_id)
        |> Expect.to_have_class!(~r/responsive-align-left/)

        AdvancedAuthor.publish(task)
        subscreen_part_id
      end

    page = OliE2E.Case.next_page(page, browser)

    Test.step "student sees the subscreen part with its authored responsive width in delivery" do
      home_task = Home.new(page, Spec.login_data(run_id, Spec.correct_student_email(run_id)))

      Home.login(home_task, :student)
      Spec.open_published_lesson(page, section_slug, @subscreen_lesson_title)

      deck = AdaptiveDeck.new(page)
      AdaptiveDeck.wait_for_deck_ready(deck)
      # Welcome Screen has no scorable part, so a single advance reaches the
      # Layer — the deck auto-descends into its one subscreen as part of the
      # same step (`findNextSequenceId`'s Layer-resolution loop).
      AdaptiveDeck.advance(deck)

      delivered_part =
        Page.locator(page, ~s|.responsive-item[data-part-id="#{subscreen_part_id}"]|)

      Expect.to_be_visible!(delivered_part, timeout: 15_000)
      Expect.to_have_class!(delivered_part, ~r/half-width/)
      Expect.to_have_class!(delivered_part, ~r/responsive-align-left/)
    end
  end
end
