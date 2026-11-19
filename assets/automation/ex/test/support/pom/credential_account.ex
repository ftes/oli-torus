defmodule OliE2E.Pom.CredentialAccount do
  @moduledoc "Port of src/systems/torus/pom/home/CredentialAccountPO.ts."

  alias Playwright.{BrowserContext, Expect, Locator, Page, Promise}

  defstruct [:page, :type]

  def new(page, type) when type in [:author, :user], do: %__MODULE__{page: page, type: type}

  def register(%{page: page} = po, account) do
    Page.goto!(page, "/#{path_segment(po)}/register")
    wait_for_live_view_ready(po)

    form = Page.locator(page, "#registration_form")
    name = form_name(po)
    form |> Locator.locator(~s|input[name="#{name}[email]"]|) |> Locator.fill!(account.email)

    form
    |> Locator.locator(~s|input[name="#{name}[given_name]"]|)
    |> Locator.fill!(account.given_name)

    form
    |> Locator.locator(~s|input[name="#{name}[family_name]"]|)
    |> Locator.fill!(account.family_name)

    form
    |> Locator.locator(~s|input[name="#{name}[password]"]|)
    |> Locator.fill!(account.password)

    form
    |> Locator.locator(~s|input[name="#{name}[password_confirmation]"]|)
    |> Locator.fill!(account.password)

    accept_cookie_consent_if_visible(po)

    Promise.all([
      Promise.async(fn ->
        Page.wait_for_url!(page, "/#{path_segment(po)}/confirm", wait_until: :commit)
      end),
      Promise.async(fn ->
        form
        |> Locator.get_by_role(:button, name: "Create account", exact: true)
        |> Locator.click!()
      end)
    ])
    |> Promise.await!()

    # The confirm-instructions LiveView must finish joining before the
    # session cookie is cleared (clear_session_cookie, called by the caller
    # right after this returns): if the join is still in flight when the
    # cookie disappears, the server rejects it as a stale session and the
    # LiveView client reloads the page on its own, racing with whatever
    # navigation the test performs next.
    wait_for_live_view_ready(po)
  end

  def confirm(%{page: page} = po, url) do
    open_account_link(po, url)
    wait_for_live_view_ready(po)
    accept_cookie_consent_if_visible(po)

    Promise.all([
      Promise.async(fn ->
        Page.wait_for_url!(page, "/#{path_segment(po)}/log_in", wait_until: :commit)
      end),
      Promise.async(fn ->
        page |> Page.get_by_role(:button, name: "Confirm", exact: true) |> Locator.click!()
      end)
    ])
    |> Promise.await!()

    page |> Page.get_by_text("Email successfully confirmed.") |> Expect.to_be_visible!()
  end

  def request_password_reset(%{page: page} = po, email) do
    Page.goto!(page, "/#{path_segment(po)}/reset_password")
    wait_for_live_view_ready(po)

    form = Page.locator(page, "#reset_password_form")
    form |> Locator.locator(~s|input[name="#{form_name(po)}[email]"]|) |> Locator.fill!(email)
    accept_cookie_consent_if_visible(po)

    Promise.all([
      Promise.async(fn -> Page.wait_for_url!(page, reset_request_destination(po)) end),
      Promise.async(fn ->
        form
        |> Locator.get_by_role(:button, name: "Send password reset instructions")
        |> Locator.click!()
      end)
    ])
    |> Promise.await!()
  end

  def reset_password(%{page: page} = po, url, password) do
    open_account_link(po, url)
    wait_for_live_view_ready(po)

    form = Page.locator(page, "#reset_password_form")
    name = form_name(po)
    form |> Locator.locator(~s|input[name="#{name}[password]"]|) |> Locator.fill!(password)

    form
    |> Locator.locator(~s|input[name="#{name}[password_confirmation]"]|)
    |> Locator.fill!(password)

    accept_cookie_consent_if_visible(po)

    Promise.all([
      Promise.async(fn ->
        Page.wait_for_url!(page, "/#{path_segment(po)}/log_in", wait_until: :commit)
      end),
      Promise.async(fn ->
        form
        |> Locator.get_by_role(:button, name: "Reset Password", exact: true)
        |> Locator.click!()
      end)
    ])
    |> Promise.await!()

    page |> Page.get_by_text("Password reset successfully.") |> Expect.to_be_visible!()
  end

  def login(%{page: page} = po, email, password, login_path \\ nil) do
    Page.goto!(page, login_path || "/#{path_segment(po)}/log_in")
    wait_for_live_view_ready(po)

    form = Page.locator(page, "#login_form")
    name = form_name(po)
    form |> Locator.locator(~s|input[name="#{name}[email]"]|) |> Locator.fill!(email)
    form |> Locator.locator(~s|input[name="#{name}[password]"]|) |> Locator.fill!(password)
    accept_cookie_consent_if_visible(po)
    form |> Locator.get_by_role(:button, name: "Sign in", exact: true) |> Locator.click!()
  end

  def expect_login_failure(%{page: page} = po) do
    Page.wait_for_url!(page, "/#{path_segment(po)}/log_in")
    page |> Page.get_by_text("Invalid email or password") |> Expect.to_be_visible!()
  end

  def expect_login_success(%{page: page} = po, destination \\ nil) do
    Page.wait_for_url!(page, destination || destination_path(po))
  end

  def expect_account_label(%{page: page}, label) do
    page |> Page.locator(~s|[data-role="account label"]|) |> Expect.to_have_text!(label)
  end

  # Clears only the session cookie so a confirmation/reset link is followed
  # anonymously, without wiping the cookie-consent choice and re-triggering
  # the consent modal on the next navigation.
  def clear_session_cookie(_po, context) do
    BrowserContext.clear_cookies!(context, name: "_oli_key")
  end

  def path_segment(%{type: :author}), do: "authors"
  def path_segment(%{type: :user}), do: "users"

  defp form_name(%{type: type}), do: Atom.to_string(type)

  defp destination_path(%{type: :author}), do: "/workspaces/course_author"
  defp destination_path(%{type: :user}), do: "/workspaces/student"

  defp reset_request_destination(%{type: :author}), do: "/authors/log_in"
  defp reset_request_destination(%{type: :user}), do: "/"

  defp open_account_link(%{page: page}, url) do
    # evaluate arguments are not included in API step titles. goto(url) exposes
    # confirmation/reset credentials even when tracing and screenshots are off.
    load = Page.wait_for_event(page, :load)
    Page.evaluate!(page, "(destination) => window.location.assign(destination)", url)
    Promise.await!(load)
  end

  defp wait_for_live_view_ready(%{page: page}) do
    page
    |> Page.locator("[data-phx-main].phx-connected")
    |> Locator.first()
    |> Expect.to_be_attached!(timeout: 15_000)
  end

  defp accept_cookie_consent_if_visible(%{page: page}) do
    consent = Page.locator(page, "#cookie_consent_display")
    accept = Locator.get_by_role(consent, :button, name: "Accept", exact: true)

    visible? =
      case Locator.is_visible(accept, timeout: 1_000) do
        {:ok, v} -> v
        _ -> false
      end

    if visible? do
      Locator.click!(accept, force: true)
      Expect.to_be_hidden!(consent)
    end
  end
end
