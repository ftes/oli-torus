defmodule OliE2E.StudentDelivery do
  @moduledoc """
  Port of the parts of tests/torus/student_delivery/support/common.ts that the
  @pr specs use. `configureStudentDeliveryRuntimeConfig` set a global; here the
  login records are returned and passed explicitly.
  """

  @default_password "changeme123456"

  def default_password, do: @default_password

  @doc "Returns `%{student: record, instructor: record, author: record, administrator: record}`."
  def configure_runtime_config(run_id, login_records) do
    Map.new(login_records, fn {role, options} -> {role, build_login_record(run_id, options)} end)
  end

  def build_login_record(
        run_id,
        %{type: type, role: role, email_prefix: email_prefix, welcome_title: welcome_title} =
          options
      ) do
    Map.merge(
      %{
        type: type,
        page_title: "OLI Torus",
        role: role,
        welcome_text: "Welcome to OLI Torus",
        welcome_title: welcome_title,
        email: "#{email_prefix}#{run_id}@example.com",
        pass: @default_password
      },
      Map.take(options, [:header, :name, :last_name])
    )
  end

  def seed_student_delivery_scenario(request, spec_dir, scenario_path, run_id) do
    response = OliE2E.Case.seed_scenario(request, spec_dir, scenario_path, %{"RUN_ID" => run_id})

    case response["outputs"] do
      nil -> raise "Scenario did not return outputs"
      outputs -> outputs
    end
  end
end
