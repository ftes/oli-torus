defmodule OliE2E.Torus.CourseAuthoring.AdvancedAuthorDeliveryTest do
  # Advanced Author lesson delivery @pr
  #
  # Own scenario seed and run id (the JS describe blocks share one); the JS
  # `afterAll` teardown only runs with PLAYWRIGHT_AUTOMATION_API_KEY (never in
  # CI): omitted.
  use OliE2E.Case, async: true

  alias OliE2E.AdvancedAuthorSpec, as: Spec
  alias OliE2E.Pom.AdvancedAuthor, as: Editor
  alias OliE2E.Tasks.{AdvancedAuthor, Home}

  @lesson_title "Advanced Author Branching Lesson"
  @correct_text "You answered correctly!"
  @incorrect_text "That is not correct."

  setup_all %{browser: browser} do
    run_id = Spec.run_id()
    section_slug = Spec.seed(browser, __DIR__, run_id)
    %{run_id: run_id, section_slug: section_slug}
  end

  @tag timeout: 240_000
  test "author builds a branching lesson with a real trap-state rule and publishes", %{
    page: page,
    run_id: run_id
  } do
    login_data = Spec.login_data(run_id)
    home_task = Home.new(page, login_data)
    task = AdvancedAuthor.new(page, login_data)
    editor = task.editor

    Home.login(home_task, :author)
    AdvancedAuthor.create_lesson(task, Spec.project_title(run_id), @lesson_title)

    mcq_id = Editor.add_component(editor, :janus_mcq)

    AdvancedAuthor.add_screen(task, "Correct Terminal")
    correct_text_id = Editor.add_component(editor, :janus_text_flow)
    Editor.set_text_flow_text(editor, correct_text_id, @correct_text)

    AdvancedAuthor.add_screen(task, "Incorrect Terminal")
    incorrect_text_id = Editor.add_component(editor, :janus_text_flow)
    Editor.set_text_flow_text(editor, incorrect_text_id, @incorrect_text)

    Editor.select_screen(editor, "Welcome Screen")
    Editor.select_part(editor, mcq_id)

    Editor.select_rule(editor, "correct")
    Editor.set_rule_condition(editor, "stage.#{mcq_id}.selectedChoice", "1")
    Editor.set_rule_destination(editor, "Correct Terminal")

    Editor.select_rule(editor, "defaultWrong")
    Editor.set_rule_destination(editor, "Incorrect Terminal")

    AdvancedAuthor.publish(task)
  end

  @tag timeout: 120_000
  test "student answering correctly reaches the correct terminal", %{
    page: page,
    run_id: run_id,
    section_slug: section_slug
  } do
    home_task = Home.new(page, Spec.login_data(run_id, Spec.correct_student_email(run_id)))

    Home.login(home_task, :student)
    Spec.open_published_lesson(page, section_slug, @lesson_title)
    Spec.answer_mcq_and_expect_terminal(page, "Option 1", @correct_text, true)
  end

  @tag timeout: 120_000
  test "student answering incorrectly reaches the incorrect terminal", %{
    page: page,
    run_id: run_id,
    section_slug: section_slug
  } do
    home_task = Home.new(page, Spec.login_data(run_id, Spec.incorrect_student_email(run_id)))

    Home.login(home_task, :student)
    Spec.open_published_lesson(page, section_slug, @lesson_title)
    Spec.answer_mcq_and_expect_terminal(page, "Option 2", @incorrect_text, false)
  end
end
