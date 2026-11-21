defmodule OliE2E.Torus.UserAccounts.CredentialAccountProvisionedRolesTest do
  # credential-based account flows - provisioned roles @pr
  use OliE2E.Case, async: true

  alias OliE2E.Mailbox
  alias OliE2E.Pom.CredentialAccount

  @moduletag :pr
  @moduletag timeout: 120_000

  @scenario_path "playwright_credential_roles.yaml"
  @seeded_password "changeme123456"

  # The `request` fixture.
  setup %{browser: browser}, do: %{request: api_request(browser)}

  test "system admin author credential lifecycle", %{
    context: context,
    page: page,
    request: request
  } do
    suffix = "#{System.os_time(:millisecond)}-#{System.unique_integer([:positive])}-admin"
    seed_scenario(request, __DIR__, @scenario_path, %{"RUN_ID" => "-#{suffix}"})

    exercise_provisioned_role_lifecycle(%{
      type: :author,
      email: "admin-#{suffix}@example.test",
      destination: "/workspaces/course_author",
      account_label: "Admin",
      context: context,
      page: page,
      request: request
    })
  end

  test "instructor user credential lifecycle", %{context: context, page: page, request: request} do
    suffix = "#{System.os_time(:millisecond)}-#{System.unique_integer([:positive])}-instructor"
    seed_scenario(request, __DIR__, @scenario_path, %{"RUN_ID" => "-#{suffix}"})

    exercise_provisioned_role_lifecycle(%{
      type: :user,
      email: "instructor-#{suffix}@example.test",
      destination: "/workspaces/instructor",
      account_label: "Instructor",
      # A plain /users/log_in submission always lands on /workspaces/student,
      # regardless of can_create_sections: the redirect target is computed
      # before current_user is assigned onto the conn. Only /instructors/log_in
      # carries an explicit request_path=/workspaces/instructor in its form
      # action, so it must be used to reach the instructor destination.
      login_path: "/instructors/log_in",
      context: context,
      page: page,
      request: request
    })
  end

  defp exercise_provisioned_role_lifecycle(
         %{
           type: type,
           email: email,
           destination: destination,
           account_label: account_label,
           context: context,
           page: page,
           request: request
         } = args
       ) do
    login_path = args[:login_path]
    new_password = "Reset-#{System.os_time(:millisecond)}-#{type}-password"
    account = CredentialAccount.new(page, type)

    CredentialAccount.login(account, email, @seeded_password, login_path)
    CredentialAccount.expect_login_success(account, destination)
    CredentialAccount.expect_account_label(account, account_label)

    CredentialAccount.clear_session_cookie(account, context)
    CredentialAccount.request_password_reset(account, email)

    reset =
      Mailbox.wait_for_email(request,
        base_url: Env.base_url(),
        recipient: email,
        subject: "Reset password",
        token: Env.scenario_token()
      )

    CredentialAccount.reset_password(
      account,
      Mailbox.extract_account_link(
        reset["html_body"],
        reset["text_body"],
        CredentialAccount.path_segment(account),
        "reset_password"
      ),
      new_password
    )

    CredentialAccount.login(account, email, @seeded_password, login_path)
    CredentialAccount.expect_login_failure(account)

    CredentialAccount.login(account, email, new_password, login_path)
    CredentialAccount.expect_login_success(account, destination)
    CredentialAccount.expect_account_label(account, account_label)
  end
end
