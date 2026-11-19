defmodule OliE2E.Torus.UserAccounts.CredentialAccountFlowsTest do
  # credential-based account flows @pr
  use OliE2E.Case, async: true

  @moduletag :pr

  alias OliE2E.Mailbox
  alias OliE2E.Pom.CredentialAccount

  @moduletag timeout: 120_000

  test "author self-service lifecycle", %{context: context, page: page, request: request} do
    exercise_self_service_lifecycle(:author, context, page, request)
  end

  test "independent learner self-service lifecycle", %{
    context: context,
    page: page,
    request: request
  } do
    exercise_self_service_lifecycle(:user, context, page, request)
  end

  defp exercise_self_service_lifecycle(type, context, page, request) do
    suffix = "#{System.os_time(:millisecond)}-#{System.unique_integer([:positive])}-#{type}"
    email = "pw-#{suffix}@example.test"
    initial_password = "Initial-#{suffix}-password"
    new_password = "Reset-#{suffix}-password"
    account = CredentialAccount.new(page, type)

    CredentialAccount.register(account, %{
      email: email,
      given_name: "Playwright",
      family_name: if(type == :author, do: "Author", else: "Learner"),
      password: initial_password
    })

    confirmation =
      Mailbox.wait_for_email(request,
        base_url: Env.base_url(),
        recipient: email,
        subject: "Confirm your email",
        token: Env.scenario_token()
      )

    CredentialAccount.clear_session_cookie(account, context)

    CredentialAccount.confirm(
      account,
      Mailbox.extract_account_link(
        confirmation["html_body"],
        confirmation["text_body"],
        CredentialAccount.path_segment(account),
        "confirm"
      )
    )

    CredentialAccount.login(account, email, initial_password)
    CredentialAccount.expect_login_success(account)

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

    CredentialAccount.login(account, email, initial_password)
    CredentialAccount.expect_login_failure(account)

    CredentialAccount.login(account, email, new_password)
    CredentialAccount.expect_login_success(account)
  end
end
