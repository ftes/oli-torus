defmodule OliE2E.Tasks.Project do
  @moduledoc """
  Port of src/systems/torus/tasks/ProjectTask.ts. Only `search_and_enter_project`,
  `create_new_project` and `publish_project` are ported (what the @pr specs use).
  """

  alias OliE2E.Utils
  alias OliE2E.Pom.{AuthorDashboard, OverviewProject, PublishProject}

  defstruct [:page, :author_db, :overview_p, :publish_p, :utils]

  def new(page) do
    %__MODULE__{
      page: page,
      author_db: AuthorDashboard.new(page),
      overview_p: OverviewProject.new(page),
      publish_p: PublishProject.new(page),
      utils: Utils.new(page)
    }
  end

  def search_and_enter_project(po, project_name) do
    AuthorDashboard.search_project(po.author_db, project_name)
    AuthorDashboard.click_project_link(po.author_db, project_name)
    OverviewProject.wait_for_editor_ready(po.overview_p)
  end

  def create_new_project(po, project_name) do
    AuthorDashboard.click_new_project_button(po.author_db)
    AuthorDashboard.fill_project_name(po.author_db, project_name)
    AuthorDashboard.click_create_button(po.author_db)
    OverviewProject.wait_for_editor_ready(po.overview_p)
    project_id = OverviewProject.get_project_id(po.overview_p)

    %{project_name: project_name, project_id: project_id}
  end

  def publish_project(po, description \\ nil) do
    try do
      PublishProject.fill_description(po.publish_p, description || "Automated publish")
    rescue
      _ -> :ok
    end

    auto_push = PublishProject.auto_push_is_checked(po.publish_p)

    if auto_push == false do
      PublishProject.click_auto_push(po.publish_p)
    end

    PublishProject.click_publish(po.publish_p)
    PublishProject.click_ok(po.publish_p)
    Utils.modal_disappears(po.utils)
  end
end
