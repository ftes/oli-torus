defmodule OliE2E.AdvancedAuthorSpec do
  @moduledoc """
  The file-level helpers of tests/torus/course_authoring/advanced-author.spec.ts
  (`runId`, `loginData`, `beforeAll` seeding, `openPublishedLesson`,
  `answerMcqAndExpectTerminal`). The JS file's three `test.describe.serial`
  blocks share one seed; the port has one ExUnit module per block, each seeding
  its own copy with its own run id (see `seed/2`).
  """

  import ExUnit.Assertions

  alias OliE2E.Pom.{AdaptiveDeck, StudentCourse}
  alias Playwright.{APIRequest, Expect, Locator, Page, Promise, Request, Response}
  alias Playwright.Test.BrowserPool

  @default_password "changeme123456"

  def default_password, do: @default_password

  # JS: `-${Date.now()}-${process.pid}`. The three modules of this spec seed at the
  # same moment, and the app slugifies the project title cut to 30 chars (the run
  # id's first digits only): the per-module number comes first so slugs differ
  # (else a concurrent insert fails on the `index_slug_families` unique constraint).
  def run_id, do: "-#{:rand.uniform(1000)}#{System.unique_integer([:positive])}-#{System.os_time(:millisecond)}-#{System.pid()}"

  def project_title(run_id), do: "Advanced Author Suite#{run_id}"

  def image_url, do: "#{OliE2E.Env.base_url()}/images/oli_torus_logo.png"
  def video_url, do: "#{OliE2E.Env.base_url()}/test/support/video-test-01.mp4"

  def correct_student_email(run_id), do: "advanced-student#{run_id}@example.com"
  def incorrect_student_email(run_id), do: "advanced-student-2#{run_id}@example.com"

  # Rebuilds the full login map, varying only which student is "student".
  def login_data(run_id, student_email \\ nil, student_name \\ "Test") do
    student_email = student_email || correct_student_email(run_id)

    %{
      author: %{
        type: "author",
        page_title: "OLI Torus",
        role: "Course Author",
        welcome_text: "Welcome to OLI Torus",
        welcome_title: "Course Author",
        email: "advanced-author#{run_id}@example.com",
        pass: @default_password,
        header: "Course Author"
      },
      student: %{
        type: "student",
        page_title: "OLI Torus",
        role: "Student",
        welcome_text: "Welcome to OLI Torus",
        welcome_title: "Hi, #{student_name}",
        email: student_email,
        name: student_name,
        last_name: "Learner",
        pass: @default_password
      }
    }
  end

  @doc """
  `test.beforeAll` seeding. Returns the section slug (the project slug is
  checked too, as in the JS).
  """
  def seed(browser, spec_dir, run_id) do
    playwright = BrowserPool.playwright(browser)
    base_url = OliE2E.Env.base_url()
    request = APIRequest.new_context!(Playwright.request(playwright), base_url: base_url, ignore_https_errors: true)

    try do
      result =
        OliE2E.Case.seed_scenario(request, spec_dir, "./playwright_advanced_author.yaml", %{"RUN_ID" => run_id})

      outputs = result["outputs"]
      title = project_title(run_id)
      project_slug = get_in(outputs, ["projects", title]) || ""
      section_slug = get_in(outputs, ["sections", title]) || ""

      assert project_slug != "", "Scenario did not return the Advanced Author project slug"
      assert section_slug != "", "Scenario did not return the Advanced Author section slug"
      section_slug
    after
      Playwright.APIRequestContext.dispose(request)
    end
  end

  def open_published_lesson(page, section_slug, title) do
    student_course = StudentCourse.new(page)

    Page.goto!(page, "/sections/#{section_slug}")
    StudentCourse.go_to_course_if_prompted(student_course)
    Page.goto!(page, "/sections/#{section_slug}/learn")
    StudentCourse.open_page(student_course, title)
  end

  # Selects an MCQ option, checks it, and expects the resulting terminal text.
  # "defaultWrong" carries two actions — the built-in "Incorrect, please try
  # again." feedback, then the authored Navigate To — so an incorrect answer
  # needs its feedback dismissed before navigation continues; `advance()`
  # handles that click-dismiss cycle generically (a correct answer, with only
  # the Navigate To action, just advances on the first click).
  #
  # The terminal text alone can't tell whether the authored rule fired: the
  # default `next` reaches Correct Terminal from Welcome, and an extra click on a
  # terminal follows its default `next` too. So it also checks the first Check's
  # evaluation — its verdict, and that no navigation goes to the default `next`.
  # It does not assert which screen the navigation targets.
  def answer_mcq_and_expect_terminal(page, option_name, terminal_text, expect_correct) do
    deck = AdaptiveDeck.new(page)
    AdaptiveDeck.wait_for_deck_ready(deck)

    mcq = page |> Page.locator("janus-mcq") |> Locator.first()
    Expect.to_be_visible!(mcq, timeout: 30_000)
    mcq |> Locator.get_by_text(option_name, exact: true) |> Locator.click!()
    mcq |> Locator.get_by_role(:radio, name: option_name) |> Expect.to_be_checked!()

    evaluation =
      Page.wait_for_response(page, fn response ->
        Request.method(Response.request(response)) == "PUT" and
          Regex.match?(~r{/activity_attempt/[^/]+$}, Response.url(response))
      end)

    AdaptiveDeck.advance(deck)
    %{"actions" => actions} = evaluation |> Promise.await!() |> Response.json!()

    destinations =
      Enum.flat_map(actions["results"], fn result ->
        result["params"]["actions"]
        |> Enum.filter(fn action -> action["type"] == "navigation" end)
        |> Enum.map(fn action -> action["params"]["target"] end)
      end)

    assert actions["correct"] == expect_correct, "The Check evaluation verdict"

    refute "next" in destinations, "The authored Navigate To destination, not the default \"next\""

    page |> Page.get_by_text(terminal_text, exact: true) |> Expect.to_be_visible!(timeout: 15_000)
  end
end
