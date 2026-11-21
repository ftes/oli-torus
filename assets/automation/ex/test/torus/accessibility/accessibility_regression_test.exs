defmodule OliE2E.Torus.Accessibility.AccessibilityRegressionTest do
  # accessibility regression coverage @pr @accessibility
  use OliE2E.Case, async: true

  import OliE2E.Accessibility

  alias OliE2E.AxeBuilder
  alias OliE2E.StudentDelivery
  alias OliE2E.Tasks.{Home, Student}
  alias OliE2E.Pom.StudentCourse
  alias Playwright.{Locator, Page}

  @moduletag :pr
  @moduletag :accessibility

  # The scenario lives with the student_delivery specs.
  @scenario_dir Path.expand("../student_delivery", __DIR__)

  setup_all %{browser: browser} do
    run_id = "-#{System.os_time(:millisecond)}"
    section_title = "MER-5489 Student Dashboard Coverage #{run_id}"

    login_data =
      StudentDelivery.configure_runtime_config(run_id, %{
        student: %{
          type: "student",
          role: "Student",
          email_prefix: "student-dashboard-coverage-student",
          welcome_title: "Hi, Coverage",
          name: "Coverage",
          last_name: "Student"
        },
        instructor: %{
          type: "instructor",
          role: "Instructor",
          email_prefix: "student-dashboard-coverage-instructor",
          welcome_title: "Instructor Dashboard",
          header: "Instructor Dashboard"
        },
        author: %{
          type: "author",
          role: "Course Author",
          email_prefix: "student-dashboard-coverage-author",
          welcome_title: "Course Author",
          header: "Course Author"
        },
        administrator: %{
          type: "administrator",
          role: "Course Author",
          email_prefix: "student-dashboard-coverage-admin",
          welcome_title: "Course Author",
          header: "Course Author"
        }
      })

    # test.beforeAll: a request context of its own (no test, so no fixture).
    api = api_request(browser)

    outputs =
      StudentDelivery.seed_student_delivery_scenario(
        api,
        @scenario_dir,
        "student-dashboard-coverage.scenario.yaml",
        run_id
      )

    Playwright.APIRequestContext.dispose(api)

    section_slug = get_in(outputs, ["sections", "student_dashboard_coverage_section"]) || ""
    project_slug = get_in(outputs, ["projects", "student_dashboard_coverage_project"]) || ""
    assert section_slug != ""
    assert project_slug != ""

    %{
      login_data: login_data,
      section_title: section_title,
      section_slug: section_slug,
      project_slug: project_slug
    }
  end

  setup %{page: page, login_data: login_data} do
    %{home: Home.new(page, login_data), student_task: Student.new(page)}
  end

  test "loading indicator has valid ARIA while visible", %{page: page, home: home} do
    Home.login(home, :student)

    try do
      Page.evaluate!(page, "() => window.dispatchEvent(new Event('phx:page-loading-start'))")
      page |> Page.locator("#nprogress .bar") |> Expect.to_be_visible!()

      results =
        AxeBuilder.new(page)
        |> AxeBuilder.include("#nprogress")
        |> AxeBuilder.with_rules(["aria-roles"])
        |> AxeBuilder.analyze!()

      assert results["violations"] == []
    after
      Page.evaluate!(page, "() => window.dispatchEvent(new Event('phx:page-loading-stop'))")
      page |> Page.locator("#nprogress") |> Expect.to_have_count!(0)
    end
  end

  test "student home has no automated accessibility violations", %{page: page, home: home} do
    Home.login(home, :student)
    scan_page_accessibility(page, "student home")
    expect_keyboard_focus(page, "a, button, input")
  end

  test "rejects accessibility scans when Tailwind CSS is missing", %{page: page, home: home} do
    Home.login(home, :student)

    Page.route!(page, "**/css/app.css", fn route ->
      Playwright.Route.fulfill!(route, status: 404, content_type: "text/css", body: "")
    end)

    Page.goto!(page, "/users/settings", wait_until: :load)

    error =
      assert_raise Playwright.ExpectError, fn ->
        scan_page_accessibility(page, "account settings without Tailwind")
      end

    assert Exception.message(error) =~ "Tailwind CSS must be loaded before scanning accessibility"
  end

  test "course outline and notes have no automated accessibility violations", %{
    page: page,
    home: home,
    student_task: student_task,
    section_title: section_title,
    section_slug: section_slug
  } do
    Home.login(home, :student)
    Student.search_project(student_task, section_title)
    Page.goto!(page, learn_path(section_slug), wait_until: :domcontentloaded)
    student_course = StudentCourse.new(page)
    StudentCourse.go_to_course_if_prompted(student_course)
    page |> Page.locator("#student_learn") |> Expect.to_be_visible!()
    scan_page_accessibility(page, "course outline")
    expect_keyboard_focus(page, "a, button, input")

    StudentCourse.open_page(student_course, "Coverage Page")
    scan_page_accessibility(page, "coverage page")

    notes_toggle = Page.get_by_role(page, :button, name: "Toggle Notes panel")
    notes_panel = Page.get_by_role(page, :complementary, name: "Notes Panel")
    Expect.to_be_visible!(notes_toggle)
    Locator.focus!(notes_toggle)
    Locator.press!(notes_toggle, "Enter")
    Expect.to_be_visible!(notes_panel)

    close_notes_button =
      notes_panel |> Locator.get_by_role(:button, name: "Close notes panel") |> Locator.first()

    Expect.to_be_visible!(close_notes_button)
    Locator.focus!(close_notes_button)
    Expect.to_be_focused!(close_notes_button)
    scan_page_accessibility(page, "notes")
    expect_keyboard_focus(page, "#annotations_panel button, #annotations_panel input")
  end

  test "scored activity has no automated accessibility violations", %{
    page: page,
    home: home,
    student_task: student_task,
    section_title: section_title,
    section_slug: section_slug
  } do
    Home.login(home, :student)
    Student.search_project(student_task, section_title)
    Page.goto!(page, learn_path(section_slug), wait_until: :domcontentloaded)
    student_course = StudentCourse.new(page)
    StudentCourse.go_to_course_if_prompted(student_course)
    page |> Page.locator("#student_learn") |> Expect.to_be_visible!()

    page
    |> Page.locator(~s|[id^="outline_rows-"] button|)
    |> Locator.first()
    |> Expect.to_be_visible!()

    StudentCourse.open_page(student_course, "Scored Activity")
    begin_attempt_button = Page.locator(page, "#begin_attempt_button")
    Expect.to_be_visible!(begin_attempt_button)
    page |> Page.locator("#bottom-bar-wrapper") |> Locator.hover!()
    page |> Page.locator("#bottom-bar") |> Expect.to_have_css!("opacity", "1")
    Locator.click!(begin_attempt_button)
    page |> Page.locator("oli-multiple-choice-delivery") |> Expect.to_be_visible!()
    page |> Page.get_by_text("Which option is correct?", exact: true) |> Expect.to_be_visible!()
    scan_page_accessibility(page, "scored activity")

    choices = Page.get_by_role(page, :radio)
    Expect.to_have_count!(choices, 2)
    choices |> Locator.first() |> Locator.focus!()
    choices |> Locator.first() |> Expect.to_be_focused!()
    page |> Page.keyboard() |> Keyboard.press!("ArrowDown")
    choices |> Locator.nth(1) |> Expect.to_be_focused!()
    page |> Page.keyboard() |> Keyboard.press!("Space")
    choices |> Locator.nth(1) |> Expect.to_have_attribute!("aria-checked", "true")
    expect_keyboard_focus(page, ~s|[role="radio"]|)
  end

  test "schedule has light and dark theme accessibility coverage", %{
    page: page,
    home: home,
    section_slug: section_slug
  } do
    Home.login(home, :student)
    Page.goto!(page, schedule_path(section_slug), wait_until: :domcontentloaded)
    scan_page_accessibility(page, "schedule", theme: :light)
    set_accessibility_theme(page, :dark)
    scan_page_accessibility(page, "schedule", theme: :dark)
    expect_keyboard_focus(page, "a, button, input")
  end

  test "account settings has no automated accessibility violations", %{page: page, home: home} do
    Home.login(home, :student)
    Page.goto!(page, "/users/settings", wait_until: :domcontentloaded)
    scan_page_accessibility(page, "account settings")
    expect_keyboard_focus(page, "a, button, input")
  end

  test "authoring dashboard and curriculum have no automated accessibility violations", %{
    page: page,
    home: home,
    project_slug: project_slug
  } do
    Home.login(home, :author)
    scan_page_accessibility(page, "authoring dashboard")
    curriculum_path = "/workspaces/course_author/#{project_slug}/curriculum"
    Page.goto!(page, curriculum_path, wait_until: :domcontentloaded)

    Expect.to_have_url!(
      page,
      Regex.compile!("/workspaces/course_author/#{project_slug}/curriculum(?:\\?|$)")
    )

    page |> Page.locator("#curriculum-container") |> Expect.to_be_visible!()

    page
    |> Page.get_by_text("Create and arrange your learning materials below.", exact: true)
    |> Expect.to_be_visible!()

    page |> Page.get_by_role(:heading, name: "Curriculum", exact: true) |> Expect.to_be_visible!()
    page |> Page.get_by_text("Coverage Page", exact: true) |> Expect.to_be_visible!()
    scan_page_accessibility(page, "authoring curriculum")
    expect_keyboard_focus(page, "a, button, input")
  end

  defp learn_path(section_slug),
    do: "/sections/#{section_slug}/learn?sidebar_expanded=true&selected_view=outline"

  defp schedule_path(section_slug),
    do: "/sections/#{section_slug}/student_schedule?sidebar_expanded=true"
end
