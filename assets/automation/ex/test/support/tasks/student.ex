defmodule OliE2E.Tasks.Student do
  @moduledoc """
  Port of src/systems/torus/tasks/StudentTask.ts (`search_project`, `validate_resource`;
  `verifyCanCreateSections` needs the instructor/new-course POs and is not used by the @pr specs).
  """

  alias OliE2E.Pom.{StudentCourse, StudentDashboard}

  defstruct [:student_db, :student_course]

  def new(page), do: %__MODULE__{student_db: StudentDashboard.new(page), student_course: StudentCourse.new(page)}

  def search_project(po, course_name) do
    StudentDashboard.wait_for_visible_courses(po.student_db)
    StudentDashboard.fill_search_input(po.student_db, course_name)
    StudentDashboard.enter_course(po.student_db, course_name)
    StudentCourse.go_to_course_if_prompted(po.student_course)
    StudentCourse.present_assignment_block(po.student_course)
  end

  def validate_resource(po, page_names) do
    StudentCourse.present_view_selector(po.student_course)

    for name <- page_names do
      StudentCourse.present_page(po.student_course, name)
    end

    :ok
  end
end
