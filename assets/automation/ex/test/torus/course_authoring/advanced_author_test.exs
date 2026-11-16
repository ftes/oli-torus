defmodule OliE2E.Torus.CourseAuthoring.AdvancedAuthorTest do
  # Advanced Author components @pr
  #
  # The component cases share one signed-in page with the editor open, so they
  # skip a login and an editor load each. Every case still reloads the editor to
  # prove its configuration persisted.
  #
  # Each describe block of the JS spec is its own module, seeding its own copy
  # of the scenario (own run id). The JS `afterAll` teardown only runs with
  # PLAYWRIGHT_AUTOMATION_API_KEY (never in CI): omitted.
  use OliE2E.Case, async: true

  alias OliE2E.AdvancedAuthorSpec, as: Spec
  alias OliE2E.Pom.AdvancedAuthor, as: Editor
  alias OliE2E.Tasks.{AdvancedAuthor, Home}

  # The fixture (captcha, site navigation) is not applied to the context made in setup_all.
  @moduletag plain: true
  @moduletag timeout: 180_000

  @component_cases [
    "static text",
    "image",
    "video",
    "multiple choice",
    "number input",
    "multiline text"
  ]

  setup_all %{browser: browser} do
    run_id = Spec.run_id()
    project_title = Spec.project_title(run_id)
    login_data = Spec.login_data(run_id)
    _section_slug = Spec.seed(browser, __DIR__, run_id)

    base_url = OliE2E.Env.base_url()

    context =
      Browser.new_context!(browser,
        base_url: base_url,
        ignore_https_errors: true,
        viewport: %{width: 1920, height: 1080}
      )

    on_exit(fn -> BrowserContext.close(context) end)
    OliE2E.Captcha.configure(context, base_url)

    page = BrowserContext.new_page!(context)
    home_task = Home.new(page, login_data)
    Home.go_to_site(home_task, "/")
    Home.login(home_task, :author)
    advanced_author_task = AdvancedAuthor.new(page, login_data)
    AdvancedAuthor.create_lesson(advanced_author_task, project_title, "Advanced Author Components")

    %{advanced_author_task: advanced_author_task}
  end

  for component_case <- @component_cases do
    @tag timeout: 120_000
    test "#{component_case} keeps its configuration after save and refresh", %{advanced_author_task: task} do
      screen_title = "#{unquote(component_case)} screen"
      editor = task.editor

      AdvancedAuthor.add_screen(task, screen_title)
      configure(unquote(component_case), editor)

      AdvancedAuthor.reload_and_open_screen(task, screen_title)
      verify_persisted(unquote(component_case), editor)
    end
  end

  @tag timeout: 150_000
  test "copy/paste and undo/redo update the screen", %{advanced_author_task: task} do
    editor = task.editor
    text_flows = Editor.parts_of_type(editor, "janus-text-flow")
    copy_text = "Original text to copy"

    AdvancedAuthor.add_screen(task, "Copy paste screen")
    part_id = Editor.add_component(editor, :janus_text_flow)
    Editor.set_text_flow_text(editor, part_id, copy_text)
    before_ids = Editor.part_ids(editor, "janus-text-flow")

    Editor.select_part(editor, part_id)
    Editor.copy_selected_part(editor)
    Editor.paste_with_toolbar(editor)

    Expect.to_have_count!(text_flows, length(before_ids) + 1)
    after_paste_ids = Editor.part_ids(editor, "janus-text-flow")
    pasted_id = Enum.find(after_paste_ids, fn id -> id not in before_ids end)
    if !pasted_id, do: raise("The pasted text flow should be on the stage")
    pasted = Editor.part(editor, pasted_id)
    Expect.to_contain_text!(pasted, copy_text)

    # The clipboard is single-use, so a second paste adds nothing.
    editor |> Editor.paste_button() |> Expect.to_be_hidden!()
    Editor.paste_with_keyboard(editor, part_id)
    Editor.wait_for_saves(editor)
    Expect.to_have_count!(text_flows, length(before_ids) + 1)

    editor |> Editor.undo_button() |> Locator.click!()
    Expect.to_have_count!(pasted, 0)
    Expect.to_have_count!(text_flows, length(before_ids))
    editor |> Editor.redo_button() |> Locator.click!()
    Expect.to_have_count!(pasted, 1)

    AdvancedAuthor.reload_and_open_screen(task, "Copy paste screen")
    Expect.to_have_count!(pasted, 1)
    Expect.to_have_count!(text_flows, length(before_ids) + 1)
  end

  @tag timeout: 150_000
  test "responsive layout arranges components side by side", %{advanced_author_task: task} do
    editor = task.editor

    AdvancedAuthor.add_screen(task, "Responsive layout screen")
    # Responsive widths only take effect once the lesson enables them.
    Editor.open_tab(editor, "Lesson")
    Editor.set_checkbox(editor, "Properties_responsiveLayout", true)
    Editor.open_tab(editor, "Screen")

    left_id = Editor.add_component(editor, :janus_text_flow)
    Editor.set_text_flow_text(editor, left_id, "Left column text")
    Editor.set_part_width(editor, left_id, "50% left")

    right_id = Editor.add_component(editor, :janus_image)
    Editor.select_part(editor, right_id)
    Editor.set_media_url(editor, "Select Image", Spec.image_url())
    Editor.set_part_width(editor, right_id, "50% right")

    AdvancedAuthor.reload_and_open_screen(task, "Responsive layout screen")

    editor |> Editor.responsive_item(left_id) |> Expect.to_have_class!(~r/half-width/)
    editor |> Editor.responsive_item(left_id) |> Expect.to_have_class!(~r/responsive-align-left/)
    editor |> Editor.responsive_item(right_id) |> Expect.to_have_class!(~r/half-width/)
    editor |> Editor.responsive_item(right_id) |> Expect.to_have_class!(~r/responsive-align-right/)
  end

  # One row per Phase 1 component. Each row authors the component on its own
  # screen, reloads the editor once every write settled, and checks that the
  # configuration survived the round trip.
  #
  # Unlike Simple Author's screens, a new Advanced Author screen's default
  # contents are not a known quantity yet, so cases locate their part by its
  # authored content/value rather than assuming a predictable id or part
  # count.
  defp configure("static text", editor) do
    part_id = Editor.add_component(editor, :janus_text_flow)
    Editor.set_text_flow_text(editor, part_id, "Static text authored by automation")
  end

  defp configure("image", editor) do
    image_id = Editor.add_component(editor, :janus_image)
    Editor.select_part(editor, image_id)
    Editor.set_media_url(editor, "Select Image", Spec.image_url())
    Editor.fill_field(editor, "custom_alt", "Torus logo")
  end

  defp configure("video", editor) do
    video_id = Editor.add_component(editor, :janus_video)
    Editor.select_part(editor, video_id)
    Editor.set_media_url(editor, "Select Video File", Spec.video_url())
  end

  defp configure("multiple choice", editor) do
    mcq_id = Editor.add_component(editor, :janus_mcq)
    Editor.select_part(editor, mcq_id)
    Editor.select_field(editor, "custom_layoutType", "horizontalLayout")
    Editor.set_checkbox(editor, "custom_multipleSelection", true)
  end

  defp configure("number input", editor) do
    number_id = Editor.add_component(editor, :janus_input_number)
    Editor.select_part(editor, number_id)
    Editor.fill_field(editor, "custom_minValue", "0")
    Editor.fill_field(editor, "custom_maxValue", "100")
    Editor.fill_field(editor, "custom_unitsLabel", "cm")
  end

  defp configure("multiline text", editor) do
    multiline_id = Editor.add_component(editor, :janus_multi_line_text)
    Editor.select_part(editor, multiline_id)
    Editor.fill_field(editor, "custom_label", "Describe your answer")
    Editor.fill_field(editor, "custom_prompt", "Type here...")
    Editor.set_checkbox(editor, "custom_showCharacterCount", false)
  end

  defp verify_persisted("static text", editor) do
    part =
      editor
      |> Editor.parts_of_type("janus-text-flow")
      |> Locator.filter(has_text: "Static text authored by automation")

    part |> Expect.message("The authored text part should be persisted") |> Expect.to_have_count!(1)
  end

  defp verify_persisted("image", editor) do
    [image_id | _] = Editor.part_ids(editor, "janus-image")
    assert image_id, "The image part should be persisted"
    Editor.select_part(editor, image_id)
    editor |> Editor.tab_panel() |> Expect.to_contain_text!(Spec.image_url())
    editor |> Editor.field("custom_alt") |> Expect.to_have_value!("Torus logo")
  end

  defp verify_persisted("video", editor) do
    [video_id | _] = Editor.part_ids(editor, "janus-video")
    assert video_id, "The video part should be persisted"
    Editor.select_part(editor, video_id)
    editor |> Editor.tab_panel() |> Expect.to_contain_text!(Spec.video_url())
  end

  defp verify_persisted("multiple choice", editor) do
    [mcq_id | _] = Editor.part_ids(editor, "janus-mcq")
    assert mcq_id, "The MCQ part should be persisted"
    Editor.select_part(editor, mcq_id)
    editor |> Editor.field("custom_layoutType") |> Expect.to_have_value!("horizontalLayout")
    editor |> Editor.field("custom_multipleSelection") |> Expect.to_be_checked!()
    # Multiple selection renders checkboxes (one per default option) instead of radios.
    editor |> Editor.part(mcq_id) |> Locator.get_by_role(:checkbox) |> Expect.to_have_count!(3)
  end

  defp verify_persisted("number input", editor) do
    [number_id | _] = Editor.part_ids(editor, "janus-input-number")
    assert number_id, "The number input part should be persisted"
    Editor.select_part(editor, number_id)
    editor |> Editor.field("custom_minValue") |> Expect.to_have_value!("0")
    editor |> Editor.field("custom_maxValue") |> Expect.to_have_value!("100")
    editor |> Editor.field("custom_unitsLabel") |> Expect.to_have_value!("cm")
  end

  defp verify_persisted("multiline text", editor) do
    [multiline_id | _] = Editor.part_ids(editor, "janus-multi-line-text")
    assert multiline_id, "The multiline text part should be persisted"
    Editor.select_part(editor, multiline_id)
    editor |> Editor.field("custom_label") |> Expect.to_have_value!("Describe your answer")
    editor |> Editor.field("custom_prompt") |> Expect.to_have_value!("Type here...")
    editor |> Editor.field("custom_showCharacterCount") |> Expect.not_to_be_checked!()
  end
end
