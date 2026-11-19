defmodule OliE2E.Pom.Login do
  @moduledoc "Port of src/systems/torus/pom/home/LoginPO.ts."

  alias OliE2E.{Verifier, Waiter}
  alias OliE2E.Pom.Navbar
  alias Playwright.{Locator, Page}

  defstruct [
    :page,
    :accept_cookies_button,
    :welcome_text,
    :main_content,
    :email_input,
    :password_input,
    :sign_in_button,
    :welcome_title
  ]

  def new(page) do
    %__MODULE__{
      page: page,
      accept_cookies_button:
        Page.locator(page, ~s|#cookie_consent_display button:has-text("Accept")|),
      welcome_text: Page.locator(page, "#main-content"),
      main_content: Page.locator(page, "#main-content"),
      email_input: Page.locator(page, "#login_form_email"),
      password_input: Page.locator(page, "#login_form_password"),
      sign_in_button: Page.locator(page, ~s|#login_form button:has-text("Sign in")|),
      welcome_title: Page.locator(page, "main h1")
    }
  end

  def accept_cookies(po) do
    Waiter.wait_for(po.accept_cookies_button, :visible)
    Locator.click!(po.accept_cookies_button)
  rescue
    _ -> IO.puts("Waiting for cookie modal and it doesn't appear")
  end

  def verify_title(po, expected_title), do: Verifier.expect_title(po.page, expected_title)

  def verify_welcome_text(po, expected_text),
    do: Verifier.expect_contain_text(po.welcome_text, expected_text)

  def verify_role(po, expected_role),
    do: Verifier.expect_contain_text(po.main_content, expected_role)

  def fill_email(po, email) do
    wait_for_login_form(po)
    Locator.click!(po.email_input)
    Locator.clear!(po.email_input)
    Locator.fill!(po.email_input, email)
    Verifier.expect_to_have_value(po.email_input, email)
  end

  def fill_password(po, password) do
    wait_for_login_form(po)
    Locator.click!(po.password_input)
    Locator.clear!(po.password_input)
    Locator.fill!(po.password_input, password)
    Verifier.expect_to_have_value(po.password_input, password)
  end

  def sign_in(po, email, password) do
    wait_for_login_form(po)
    Locator.fill!(po.email_input, email)
    Locator.fill!(po.password_input, password)
    Verifier.expect_to_have_value(po.email_input, email)
    Verifier.expect_to_have_value(po.password_input, password)
    click_sign_in_button(po)
  end

  def click_sign_in_button(po), do: Locator.click!(po.sign_in_button)

  defp wait_for_login_form(po) do
    Waiter.wait_for_load_state(po.page)

    try do
      Waiter.wait_for(po.page |> Page.locator("div.phx-connected") |> Locator.first(), :attached)
      Waiter.wait_for(po.page |> Page.locator("div.phx-loading") |> Locator.first(), :detached)
    rescue
      # Some login pages may render without a LiveView root; the form checks below are the source of truth.
      _ -> :ok
    end

    Waiter.wait_for(po.email_input, :visible)
    Waiter.wait_for(po.password_input, :visible)
    Verifier.expect_is_enabled(po.email_input)
    Verifier.expect_is_enabled(po.password_input)
    Verifier.expect_is_enabled(po.sign_in_button)
  end

  @doc "`role` is a `TYPE_USER` string: `\"student\"`, `\"instructor\"`, `\"author\"` or `\"administrator\"`."
  def select_role_account(po, role) do
    navbarco = Navbar.new(po.page)

    if role == "student", do: Navbar.click_logo(navbarco)
    if role == "instructor", do: Navbar.go_to_instructors_login(navbarco)
    if role in ["author", "administrator"], do: Navbar.go_to_authors_login(navbarco)
  end

  def verify_welcome_title(po, expected_title),
    do: Verifier.expect_contain_text(po.welcome_title, expected_title)
end
