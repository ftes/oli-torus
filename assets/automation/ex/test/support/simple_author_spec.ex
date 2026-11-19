defmodule OliE2E.SimpleAuthorSpec do
  @moduledoc """
  The file-level helpers of tests/torus/course_authoring/simple-author.spec.ts
  (`runId`, `loginData`, `beforeAll` seeding). The JS file's two
  `test.describe.serial` blocks share one seed; the port has one ExUnit module per
  block, each seeding its own copy with its own run id (see `seed/3`).
  """

  @default_password "changeme123456"

  def run_id, do: OliE2E.Helpers.run_id()

  def project_title(run_id), do: "Simple Author Suite#{run_id}"

  def video_url, do: "#{OliE2E.Env.base_url()}/test/support/video-test-01.mp4"

  def login_data(run_id) do
    %{
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
  end

  @doc """
  `test.beforeAll` seeding: returns the section slug.

  The PR job runs against an ephemeral database, so the JS `afterAll` teardown only
  runs when an automation API key is available (local runs and persistent
  deployments): not ported.
  """
  def seed(browser, spec_dir, run_id) do
    OliE2E.Case.seed_authoring_scenario(
      browser,
      spec_dir,
      "./playwright_simple_author.yaml",
      run_id,
      project_title(run_id),
      "Simple Author"
    )
  end
end
