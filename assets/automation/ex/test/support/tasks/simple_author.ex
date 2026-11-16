defmodule OliE2E.Tasks.SimpleAuthor do
  @moduledoc """
  Port of src/systems/torus/tasks/SimpleAuthorTask.ts.

  Business workflows for the adaptive Simple Author editor. Fine-grained
  editor interactions and assertions live on `editor` (OliE2E.Pom.SimpleAuthor).
  The `@step` decorators are dropped.
  """

  alias OliE2E.Pom.SimpleAuthor, as: Editor
  alias OliE2E.Tasks.{Curriculum, Home, Project}

  defstruct [:editor, :home_task, :project_task, :curriculum_task]

  def new(page, login_data) do
    %__MODULE__{
      editor: Editor.new(page),
      home_task: Home.new(page, login_data),
      project_task: Project.new(page),
      curriculum_task: Curriculum.new(page)
    }
  end

  # Creates a Simple Author lesson in the project and leaves its editor open.
  def create_lesson(task, project_title, lesson_title) do
    Project.search_and_enter_project(task.project_task, project_title)
    Home.enter_to_curriculum(task.home_task)
    Curriculum.create_adaptive_page_in_simple_author(task.curriculum_task, true, lesson_title)
    Editor.wait_for_editor_loaded(task.editor)
    Editor.wait_for_saves(task.editor)
  end

  def add_screen(task, title, type), do: Editor.add_screen(task.editor, title, type)

  # Reloads the editor once every write settled and reopens the given screen.
  def reload_and_open_screen(task, title) do
    Editor.reload_editor(task.editor)
    Editor.switch_to_screen_panel(task.editor)
    Editor.select_screen(task.editor, title)
  end

  def publish(task) do
    Editor.wait_for_saves(task.editor)
    Home.enter_to_publish(task.home_task)
    Project.publish_project(task.project_task)
  end
end
