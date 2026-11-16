defmodule OliE2E.Torus.CourseAuthoring.SimpleAuthorTest do
  # Simple Author components @pr
  #
  # The component cases share one signed-in page with the editor open, so they
  # skip a login and an editor load each. Every case still reloads the editor to
  # prove its configuration persisted.
  #
  # test.describe.serial: one module, the tests run in definition order (`mix test --seed 0`).
  # The second describe of simple-author.spec.ts ('Simple Author lesson delivery') is in
  # simple_author_delivery_test.exs, seeding a scenario copy of its own.
  use OliE2E.Case, async: true

  alias OliE2E.Pom.SimpleAuthor, as: Editor
  alias OliE2E.Tasks.{Home, SimpleAuthor}
  alias Playwright.{BrowserContext, Locator}

  # test.beforeAll uses test.setTimeout(180_000); the shared page is not the per-test one.
  @moduletag timeout: 180_000
  @moduletag site: false

  @default_password "changeme123456"

  # One row per Phase 1 component. Each row authors the component on its own
  # screen, reloads the editor once every write settled, and checks that the
  # configuration survived the round trip.
  @component_cases [
    {"static text", "Instructional Screen"},
    {"image", "Instructional Screen"},
    {"video", "Instructional Screen"},
    {"multiple choice", "Multiple Choice"},
    {"multi-select", "Multiple Choice"},
    {"hub and spoke", "Hub and Spoke"}
  ]

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

    # A context of its own: no fixture defaults, so the options are explicit and the captcha
    # init script is added by hand.
    context =
      Browser.new_context!(browser,
        base_url: base_url,
        ignore_https_errors: true,
        viewport: %{width: 1920, height: 1080}
      )

    OliE2E.Captcha.configure(context, base_url)
    page = BrowserContext.new_page!(context)
    home_task = Home.new(page, login_data)
    Home.go_to_site(home_task, "/")
    Home.login(home_task, :author)
    simple_author_task = SimpleAuthor.new(page, login_data)
    SimpleAuthor.create_lesson(simple_author_task, project_title, "Simple Author Components")
    Editor.switch_to_screen_panel(simple_author_task.editor)

    on_exit(fn -> BrowserContext.close(context) end)

    %{simple_author_task: simple_author_task, base_url: base_url}
  end

  for {name, screen_type} <- @component_cases do
    @tag timeout: 120_000
    test "#{name} keeps its configuration after save and refresh", %{
      simple_author_task: task,
      base_url: base_url
    } do
      name = unquote(name)
      screen_title = "#{name} screen"
      editor = task.editor

      SimpleAuthor.add_screen(task, screen_title, unquote(screen_type))
      configure(name, editor, base_url)

      SimpleAuthor.reload_and_open_screen(task, screen_title)
      verify_persisted(name, editor, base_url)
    end
  end

  @tag timeout: 150_000
  test "copy/paste and undo/redo update the screen and respect question limits", %{
    simple_author_task: task
  } do
    editor = task.editor
    text_flows = Editor.parts_of_type(editor, "janus-text-flow")

    SimpleAuthor.add_screen(task, "Copy paste screen", "Instructional Screen")
    Expect.to_have_count!(text_flows, 3)

    Editor.select_part(editor, "para-1")
    Editor.copy_selected_part(editor)
    Editor.paste_with_toolbar(editor)

    Expect.to_have_count!(text_flows, 4)

    pasted_id =
      editor
      |> Editor.part_ids("janus-text-flow")
      |> Enum.find(fn id -> id not in ["header-1", "para-1", "para-2"] end)

    if !pasted_id, do: raise("The pasted text flow should be on the stage")
    assert pasted_id =~ ~r/^janus-text-flow-\d+$/
    pasted = Editor.part(editor, pasted_id)

    Expect.to_contain_text!(
      pasted,
      editor |> Editor.part("para-1") |> Locator.inner_text!() |> String.trim() |> String.slice(0, 40)
    )

    # The clipboard is single-use, so a second paste adds nothing.
    Expect.to_be_hidden!(Editor.paste_button(editor))
    Editor.paste_with_keyboard(editor, "para-2")
    Editor.wait_for_saves(editor)
    Expect.to_have_count!(text_flows, 4)

    editor |> Editor.undo_button() |> Locator.click!()
    Expect.to_have_count!(pasted, 0)
    Expect.to_have_count!(text_flows, 3)
    editor |> Editor.redo_button() |> Locator.click!()
    Expect.to_have_count!(pasted, 1)

    SimpleAuthor.reload_and_open_screen(task, "Copy paste screen")
    Expect.to_have_count!(pasted, 1)
    Expect.to_have_count!(text_flows, 4)

    # A screen keeps a single question component, even through paste.
    SimpleAuthor.add_screen(task, "Paste limits screen", "Multiple Choice")
    Editor.select_part(editor, "question-1")
    Editor.copy_selected_part(editor)
    Expect.to_be_disabled!(Editor.paste_button(editor))
    Editor.paste_with_keyboard(editor, "question-1")

    Expect.to_contain_text!(
      Editor.paste_blocked_modal(editor),
      "Only one question component per screen is allowed"
    )

    editor
    |> Editor.paste_blocked_modal()
    |> Locator.get_by_role(:button, name: "Close")
    |> Locator.first()
    |> Locator.click!()

    Expect.to_be_hidden!(Editor.paste_blocked_modal(editor))
    Expect.to_have_count!(Editor.parts_of_type(editor, "janus-mcq"), 1)

    # Static components can still be pasted next to the question.
    Editor.select_part(editor, "para-1")
    Editor.copy_selected_part(editor)
    Editor.paste_with_toolbar(editor)
    Expect.to_have_count!(text_flows, 4)
    Expect.to_have_count!(Editor.parts_of_type(editor, "janus-mcq"), 1)
  end

  # ------------------------------------------------------------ component cases

  defp configure("static text", editor, _base_url) do
    Editor.set_text_flow_text(editor, "para-1", "Static text authored by automation")
  end

  defp configure("image", editor, base_url) do
    image_id = Editor.add_component(editor, "janus_image")
    Editor.select_part(editor, image_id)
    Editor.set_media_url(editor, "Select Image", image_url(base_url))
    Editor.fill_field(editor, "custom_alt", "Torus logo")
  end

  defp configure("video", editor, base_url) do
    video_id = Editor.add_component(editor, "janus_video")
    Editor.select_part(editor, video_id)
    Editor.set_media_url(editor, "Select Video File", video_url(base_url))
  end

  defp configure("multiple choice", editor, _base_url) do
    Editor.select_part(editor, "question-1")
    Editor.set_mcq_correct_answer(editor, "Option 2")
    Editor.fill_field(editor, "custom_correctFeedback", "Correct, well done")
    Editor.fill_field(editor, "custom_incorrectFeedback", "Not quite, try again")
  end

  defp configure("multi-select", editor, _base_url) do
    Editor.select_part(editor, "question-1")
    Editor.set_checkbox(editor, "custom_multipleSelection", true)

    editor
    |> Editor.part("question-1")
    |> Locator.get_by_role(:checkbox)
    |> Expect.to_have_count!(3)

    Editor.set_mcq_correct_option(editor, "Option 3", true)
  end

  defp configure("hub and spoke", editor, _base_url) do
    Editor.select_part(editor, "question-1")
    Editor.add_hub_spoke(editor, "Spoke 4")
    editor |> Editor.part("question-1") |> Expect.to_contain_text!("Spoke 4")
    Editor.select_field(editor, "custom_requiredSpoke", "2")
    Editor.fill_field(editor, "custom_correctFeedback", "All required spokes visited")
  end

  defp verify_persisted("static text", editor, _base_url) do
    editor |> Editor.part("para-1") |> Expect.to_contain_text!("Static text authored by automation")
  end

  defp verify_persisted("image", editor, base_url) do
    image_id = editor |> Editor.part_ids("janus-image") |> List.first()
    assert image_id, "The image part should be persisted"
    Editor.select_part(editor, image_id)
    editor |> Editor.tab_panel() |> Expect.to_contain_text!(image_url(base_url))
    editor |> Editor.field("custom_alt") |> Expect.to_have_value!("Torus logo")
  end

  defp verify_persisted("video", editor, base_url) do
    video_id = editor |> Editor.part_ids("janus-video") |> List.first()
    assert video_id, "The video part should be persisted"
    Editor.select_part(editor, video_id)
    editor |> Editor.tab_panel() |> Expect.to_contain_text!(video_url(base_url))
  end

  defp verify_persisted("multiple choice", editor, _base_url) do
    Editor.select_part(editor, "question-1")
    editor |> Editor.field("custom_correctFeedback") |> Expect.to_have_value!("Correct, well done")
    editor |> Editor.field("custom_incorrectFeedback") |> Expect.to_have_value!("Not quite, try again")
    editor |> Editor.mcq_correct_answer_select() |> Expect.to_have_value!("1")

    editor
    |> Editor.part("question-1")
    |> Locator.get_by_role(:radio)
    |> Expect.to_have_count!(3)
  end

  defp verify_persisted("multi-select", editor, _base_url) do
    Editor.select_part(editor, "question-1")
    editor |> Editor.field("custom_multipleSelection") |> Expect.to_be_checked!()

    editor
    |> Editor.part("question-1")
    |> Locator.get_by_role(:checkbox)
    |> Expect.to_have_count!(3)

    editor |> Editor.mcq_correct_answer_checkbox("Option 1") |> Expect.to_be_checked!()
    editor |> Editor.mcq_correct_answer_checkbox("Option 2") |> Expect.not_to_be_checked!()
    editor |> Editor.mcq_correct_answer_checkbox("Option 3") |> Expect.to_be_checked!()
  end

  defp verify_persisted("hub and spoke", editor, _base_url) do
    Editor.select_part(editor, "question-1")
    editor |> Editor.field("custom_requiredSpoke") |> Expect.to_have_value!("2")

    editor
    |> Editor.field("custom_correctFeedback")
    |> Expect.to_have_value!("All required spokes visited")

    editor |> Editor.part("question-1") |> Expect.to_contain_text!("Spoke 4")
  end

  defp image_url(base_url), do: "#{base_url}/images/oli_torus_logo.png"
  defp video_url(base_url), do: "#{base_url}/test/support/video-test-01.mp4"
end
