defmodule OliE2E.Case do
  @moduledoc """
  Port of src/core/fixture/my-fixture.ts: the `context` fixture configures the
  captcha, the auto `forEachTest` fixture opens the site, `request` is the API
  request fixture, and `seed_scenario` seeds data from a scenario file next to
  the spec.

  `@moduletag plain: true` skips both fixtures (a spec importing `test` from
  '@playwright/test'); `@moduletag site: false` skips only the site navigation
  (a spec replacing `forEachTest`, or one whose tests work on a `setup_all` page).
  """

  use ExUnit.CaseTemplate

  using opts do
    quote do
      use Playwright.Case, unquote(opts)

      import OliE2E.Case, only: [seed_scenario: 4, seed_scenario: 3, api_request: 1]
      alias OliE2E.Env

      setup {OliE2E.Case, :fixtures}
    end
  end

  alias OliE2E.Env
  alias Playwright.{APIRequest, Browser, BrowserContext, Page}
  alias Playwright.Test.BrowserPool

  @doc false
  def fixtures(%{browser: browser, context: context, page: page} = ctx) do
    base_url = Playwright.Test.info().use[:base_url]
    plain? = Map.get(ctx, :plain, false)
    unless plain?, do: OliE2E.Captcha.configure(context, base_url)

    if not plain? and Map.get(ctx, :site, true) do
      Page.goto!(page, base_url)
    end

    %{request: api_request(browser), base_url: base_url}
  end

  @doc """
  A `test.describe.serial` block runs as one test with a step per JS test. Each JS
  test gets its own context and page from the fixtures: this closes the previous
  step's context and returns a new page, with the captcha configured and the site open.
  """
  def next_page(previous_page, browser) do
    previous_page |> Page.context() |> BrowserContext.close!()

    base_url = Playwright.Test.info().use[:base_url]
    context = Browser.new_context!(browser)
    OliE2E.Captcha.configure(context, base_url)
    page = BrowserContext.new_page!(context)
    Page.goto!(page, base_url)
    page
  end

  @doc "The `request` fixture: an API request context (use it in `setup_all` too, and dispose it there)."
  def api_request(browser) do
    APIRequest.new_context!(Playwright.request(BrowserPool.playwright(browser)))
  end

  @doc """
  Seeds a scenario file of the JS suite: `spec_dir` is the port's `__DIR__`
  (`ex/test/torus/x`), mirroring the JS spec's directory `tests/torus/x`.
  """
  def seed_scenario(request, spec_dir, relative_path, params \\ %{}) do
    js_dir = String.replace(spec_dir, "/automation/ex/test", "/automation/tests")

    OliE2E.Scenario.seed_from_file(
      request,
      Path.expand(relative_path, js_dir),
      params,
      Env.base_url(),
      Env.scenario_token()
    )
  end
end
