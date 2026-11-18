defmodule OliE2E.Torus.CourseAuthoring.SimpleAuthorDeliveryTest do
  # Simple Author lesson delivery @pr
  #
  # Second describe of simple-author.spec.ts (test.describe.serial: two dependent tests, run in
  # definition order). In JS both describes share one seeded scenario; here each module seeds its
  # own copy (own RUN_ID, so own project title and login data), to run in parallel.
  use OliE2E.Case, async: true

  alias OliE2E.Pom.{AdaptiveDeck, StudentCourse}
  alias OliE2E.Tasks.{Home, SimpleAuthor}
  alias OliE2E.Pom.SimpleAuthor, as: Editor
  alias Playwright.{Expect, Locator, Page}

  @default_password "changeme123456"
  @desktop_viewport %{width: 1280, height: 900}
  @phone_viewport %{width: 500, height: 900}

  @lesson_title "Simple Author Delivery"
  @quiz_title "Quiz Screen"
  @slider_title "Slider Screen"
  @slider_feedback "Close, 2.5 is the halfway mark"

  setup_all %{browser: browser} do
    base_url = Env.base_url()
    run_id = OliE2E.Helpers.run_id()
    project_title = "Simple Author Suite#{run_id}"

    login_data = %{
      author: %{
        type: "author",
        page_title: "OLI Torus",
        role: "Course Author",
        welcome_text: "Welcome to OLI Torus",
        welcome_title: "Course Author",
        email: "simple-author#{run_id}@example.com",
        pass: @default_password,
        header: "Course Author"
      },
      student: %{
        type: "student",
        page_title: "OLI Torus",
        role: "Student",
        welcome_text: "Welcome to OLI Torus",
        welcome_title: "Hi, Test",
        email: "simple-student#{run_id}@example.com",
        name: "Test",
        last_name: "Learner",
        pass: @default_password
      }
    }

    api = OliE2E.Case.api_request(browser)
    result = seed_scenario(api, __DIR__, "playwright_simple_author.yaml", %{"RUN_ID" => run_id})
    Playwright.APIRequestContext.dispose(api)

    outputs = result["outputs"] || %{}
    project_slug = get_in(outputs, ["projects", project_title]) || ""
    section_slug = get_in(outputs, ["sections", project_title]) || ""
    assert project_slug != "", "Scenario did not return the Simple Author project slug"
    assert section_slug != "", "Scenario did not return the Simple Author section slug"

    # The PR job runs against an ephemeral database, so the JS teardown only runs when an
    # automation API key is available (local runs and persistent deployments): omitted here.

    %{
      login_data: login_data,
      project_title: project_title,
      section_slug: section_slug,
      video_url: "#{base_url}/test/support/video-test-01.mp4"
    }
  end

  @tag timeout: 300_000
  test "author validates, scores, and publishes a multi-screen lesson", %{
    page: page,
    login_data: login_data,
    project_title: project_title,
    video_url: video_url
  } do
    home_task = Home.new(page, login_data)
    task = SimpleAuthor.new(page, login_data)
    editor = task.editor

    Home.login(home_task, :author)
    SimpleAuthor.create_lesson(task, project_title, @lesson_title)
    Editor.switch_to_screen_panel(editor)

    # Responsive layout: a half-width paragraph and image share a row on the
    # welcome screen, followed by a full-width paragraph.
    Editor.select_screen(editor, "Welcome Screen")
    Editor.set_part_width(editor, "para-1", "50% left")
    Editor.set_part_width(editor, "image-1", "50% right")
    Editor.set_part_width(editor, "para-2", "100%")
    video_id = Editor.add_component(editor, "janus_video")
    Editor.select_part(editor, video_id)
    Editor.set_media_url(editor, "Select Video File", video_url)

    SimpleAuthor.add_screen(task, @quiz_title, "Multiple Choice")
    Editor.select_part(editor, "question-1")
    Editor.fill_field(editor, "custom_incorrectFeedback", "Not quite, try again")
    Editor.open_tab(editor, "Screen")
    Editor.fill_field(editor, "checkButton_checkButtonLabel", "Check Answer")
    Editor.select_field(editor, "max_maxAttempt", "4")
    Editor.fill_field(editor, "max_maxScore", "10")

    # Decimal values in slider advanced feedback must not be truncated.
    SimpleAuthor.add_screen(task, @slider_title, "Slider")
    Editor.select_part(editor, "question-1")
    Editor.fill_field(editor, "custom_maximum", "5")
    Editor.fill_field(editor, "custom_snapInterval", "0.5")
    Editor.fill_field(editor, "custom_answer_correctAnswer", "4")
    Editor.add_slider_feedback_rule(editor, "Equal to", ["2.5"], @slider_feedback)

    SimpleAuthor.reload_and_open_screen(task, @slider_title)
    Editor.select_part(editor, "question-1")
    editor |> Editor.field("custom_snapInterval") |> Expect.to_have_value!("0.5")
    editor |> Editor.slider_feedback_rules() |> Expect.to_have_count!(1)

    editor
    |> Editor.slider_feedback_rules()
    |> Locator.locator(~s|input[type="number"]|)
    |> Expect.to_have_value!("2.5")

    editor
    |> Editor.slider_feedback_rules()
    |> Locator.locator("textarea")
    |> Expect.to_have_value!(@slider_feedback)

    Editor.select_screen(editor, @quiz_title)
    Editor.open_tab(editor, "Screen")
    editor |> Editor.field("checkButton_checkButtonLabel") |> Expect.to_have_value!("Check Answer")
    editor |> Editor.field("max_maxAttempt") |> Expect.to_have_value!("4")
    editor |> Editor.field("max_maxScore") |> Expect.to_have_value!("10")
    editor |> Editor.scoring_overview_button() |> Locator.click!()
    editor |> Editor.scoring_overview() |> Expect.to_contain_text!(@quiz_title)
    editor |> Editor.scoring_overview() |> Expect.to_contain_text!("Sum of All Scores: 10")
    Editor.close_scoring_overview(editor)

    # Screen validation and navigation are configured in the flowchart.
    Editor.switch_to_flowchart(editor)
    Editor.select_flowchart_screen(editor, @quiz_title)
    editor |> Editor.validation_errors() |> Expect.to_contain_text!(["No path leads to this screen"])

    Editor.set_paths(editor, "Welcome Screen", [{"Always", @quiz_title}])

    Editor.set_paths(editor, @quiz_title, [
      {"Correct", @slider_title},
      {"Any Incorrect", "End of Lesson"}
    ])

    Editor.set_paths(editor, @slider_title, [
      {"Correct", "End of Lesson"},
      {"Any Incorrect", "End of Lesson"}
    ])

    for screen <- ["Welcome Screen", @quiz_title, @slider_title] do
      Editor.select_flowchart_screen(editor, screen)

      editor
      |> Editor.validation_errors()
      |> Expect.message("#{screen} should be valid")
      |> Expect.to_have_count!(0)

      editor
      |> Editor.flowchart_node(screen)
      |> Expect.not_to_contain_text!("This screen is not validated.")
    end

    SimpleAuthor.publish(task)
  end

  @tag timeout: 240_000
  test "student navigates, gets check-button feedback, and sees the responsive layout", %{
    page: page,
    login_data: login_data,
    section_slug: section_slug
  } do
    home_task = Home.new(page, login_data)
    deck = AdaptiveDeck.new(page)

    Home.login(home_task, :student)
    open_lesson_as_student(page, @lesson_title, section_slug)
    AdaptiveDeck.wait_for_deck_ready(deck)
    Page.set_viewport_size!(page, @desktop_viewport)

    # Responsive layout: side by side on desktop, stacked on a phone viewport.
    Expect.to_be_attached!(Page.locator(page, ~s|[data-adaptive-responsive-layout="true"]|))
    left = delivery_item(page, "para-1")
    right = delivery_item(page, "image-1")
    full_width = delivery_item(page, "para-2")
    Expect.to_have_class!(left, ~r/half-width/)
    Expect.to_have_class!(left, ~r/responsive-align-left/)
    Expect.to_have_class!(right, ~r/half-width/)
    Expect.to_have_class!(right, ~r/responsive-align-right/)
    Expect.to_have_class!(full_width, ~r/full-width/)
    expect_side_by_side(left, right)

    Page.set_viewport_size!(page, @phone_viewport)
    expect_stacked(left, right)
    Page.set_viewport_size!(page, @desktop_viewport)
    expect_side_by_side(left, right)

    # The video authored on the welcome screen loads in delivery.
    expect_video_loaded(Page.locator(page, "janus-video video"))

    deck |> AdaptiveDeck.footer_button() |> Locator.click!()
    deck |> AdaptiveDeck.footer_button() |> Expect.to_have_text!("Check Answer", timeout: 30_000)

    # A wrong first answer shows the authored feedback and keeps the student on the screen.
    mcq = Page.locator(page, "janus-mcq")
    mcq |> Locator.get_by_text("Option 2", exact: true) |> Locator.click!()
    AdaptiveDeck.submit_check(deck)
    AdaptiveDeck.wait_for_feedback_open(deck)
    page |> Page.locator(".feedbackContainer") |> Expect.to_contain_text!("Not quite, try again")
    Expect.to_be_visible!(mcq)

    # Answering correctly and checking again follows the "Correct" path to the slider screen.
    # With the feedback still open, the footer control re-checks the current
    # answer, so the student just changes the answer and checks again.
    correct_option = Locator.get_by_role(mcq, :radio, name: "Option 1")
    mcq |> Locator.get_by_text("Option 1", exact: true) |> Locator.click!()
    Expect.to_be_checked!(correct_option)
    deck |> AdaptiveDeck.footer_button() |> Locator.click!()
    slider = Page.locator(page, ~s|janus-slider input[type="range"]|)
    advance_past_feedback(deck, slider)

    # Each extra attempt costs maxScore / maxAttempt (10 / 4), so a correct
    # answer on the second attempt scores 7.50.
    deck |> AdaptiveDeck.score() |> Expect.to_contain_text!("7.50")

    # The decimal advanced-feedback rule matches the learner's value.
    Locator.fill!(slider, "2.5")
    Expect.to_have_value!(slider, "2.5")
    AdaptiveDeck.submit_check(deck)
    AdaptiveDeck.wait_for_feedback_open(deck)
    page |> Page.locator(".feedbackContainer") |> Expect.to_contain_text!(@slider_feedback)
  end

  defp open_lesson_as_student(page, lesson_title, section_slug) do
    student_course = StudentCourse.new(page)

    Page.goto!(page, "/sections/#{section_slug}")
    StudentCourse.go_to_course_if_prompted(student_course)
    Page.goto!(page, "/sections/#{section_slug}/learn")
    StudentCourse.open_page(student_course, lesson_title)
  end

  defp delivery_item(page, part_id) do
    Page.locator(page, ~s|.responsive-item[data-part-id="#{part_id}"]|)
  end

  # Clicks through the post-check feedback until the target screen renders.
  defp advance_past_feedback(deck, target) do
    done =
      Enum.reduce_while(0..2, false, fn _attempt, _ ->
        if match?({:ok, true}, Locator.is_visible(target)) do
          {:halt, true}
        else
          if AdaptiveDeck.feedback_visible(deck), do: AdaptiveDeck.acknowledge_feedback(deck)
          # .catch(() => undefined)
          Locator.wait_for(target, state: :visible, timeout: 10_000)
          {:cont, false}
        end
      end)

    unless done, do: Expect.to_be_visible!(target)
  end

  defp expect_side_by_side(left, right) do
    Expect.poll!(
      fn ->
        a = Locator.bounding_box!(left)
        b = Locator.bounding_box!(right)
        a != nil and b != nil and abs(a.y - b.y) < 2 and a.x + a.width <= b.x + 1
      end,
      &assert(&1 == true)
    )
  end

  # Stacked items share the column and do not overlap, in whichever order they render.
  defp expect_stacked(first, second) do
    Expect.poll!(
      fn ->
        a = Locator.bounding_box!(first)
        b = Locator.bounding_box!(second)

        if a == nil or b == nil do
          false
        else
          same_column = abs(a.x - b.x) < 2 and abs(a.width - b.width) < 2
          no_overlap = b.y >= a.y + a.height - 1 or a.y >= b.y + b.height - 1
          same_column and no_overlap
        end
      end,
      &assert(&1 == true)
    )
  end

  # The media element reached HAVE_METADATA (readyState >= 1) without a media error.
  defp expect_video_loaded(video) do
    Expect.to_be_attached!(video)

    Expect.poll!(
      fn ->
        Locator.evaluate!(video, "(element) => element.readyState >= 1 && element.error === null")
      end,
      &assert(&1 == true),
      message: "The authored video should load in delivery"
    )
  end
end
