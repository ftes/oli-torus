defmodule OliE2E.Torus.UserAccounts.CaptchaRejectionTest do
  # registration captcha authorization @pr
  use OliE2E.Case, async: true

  # imports `test` from '@playwright/test', not the my-fixture one
  @moduletag plain: true

  alias Playwright.{Locator, Page}

  for type <- ["user", "author"], credential <- ["missing", "incorrect"] do
    test "#{type} registration rejects a #{credential} credential", %{
      context: context,
      page: page,
      base_url: base_url
    } do
      type = unquote(type)
      credential = unquote(credential)

      OliE2E.Captcha.configure(
        context,
        base_url,
        if(credential == "missing", do: "", else: "incorrect-token")
      )

      Page.goto!(page, "/#{type}s/register")
      Expect.to_be_attached!(Page.locator(page, "[data-phx-main].phx-connected"))

      form = Page.locator(page, "#registration_form")

      fields = [
        email: "captcha-#{type}-#{credential}-#{System.os_time(:millisecond)}@example.test",
        given_name: "Captcha",
        family_name: "Rejection",
        password: "Valid-password-123!",
        password_confirmation: "Valid-password-123!"
      ]

      for {name, value} <- fields do
        form |> Locator.locator(~s|input[name="#{type}[#{name}]"]|) |> Locator.fill!(value)
      end

      accept_cookies =
        page
        |> Page.locator("#cookie_consent_display")
        |> Locator.get_by_role(:button, name: "Accept", exact: true)

      Locator.click!(accept_cookies)
      Expect.to_be_hidden!(accept_cookies)

      form |> Locator.get_by_role(:button, name: "Create account", exact: true) |> Locator.click!()

      form |> Locator.get_by_text("reCAPTCHA failed, please try again") |> Expect.to_be_visible!()
      Expect.to_have_url!(page, Regex.compile!("/#{type}s/register$"))
    end
  end
end
