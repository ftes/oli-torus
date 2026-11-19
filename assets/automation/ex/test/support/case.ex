defmodule OliE2E.Case do
  @moduledoc """
  Port of src/core/fixture/my-fixture.ts: the `context` fixture configures the
  captcha, the auto `forEachTest` fixture opens the site, `api_request/1` is the
  API request fixture (`request`), and `seed_scenario` seeds data from a scenario
  file next to the spec.

  `@moduletag plain: true` skips both fixtures (a spec importing `test` from
  '@playwright/test', or a `describe.serial` whose `beforeAll` makes its own page);
  `@moduletag site: false` skips only the site navigation (a spec replacing
  `forEachTest`).
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

  import ExUnit.Assertions

  alias OliE2E.Env
  alias Playwright.{APIRequest, Browser, BrowserContext, Page}
  alias Playwright.Test.BrowserPool

  @doc false
  def fixtures(%{context: context, page: page} = ctx) do
    base_url = Playwright.Test.info().use[:base_url]
    plain? = Map.get(ctx, :plain, false)
    unless plain?, do: OliE2E.Captcha.configure(context, base_url)

    if not plain? and Map.get(ctx, :site, true) do
      Page.goto!(page, base_url)
    end

    %{base_url: base_url}
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

  @doc """
  The `request` fixture: an API request context. A test's is disposed at its end; in
  `setup_all`, dispose it there.
  """
  def api_request(browser) do
    APIRequest.new_context!(Playwright.request(BrowserPool.playwright(browser)))
  end

  @doc """
  The `beforeAll` of simple-author.spec.ts and advanced-author.spec.ts: seeds the
  spec's scenario with `RUN_ID` and returns the section slug of `project_title`,
  checking its project slug too (`name` is the suite's name in the messages).
  """
  def seed_authoring_scenario(browser, spec_dir, scenario, run_id, project_title, name) do
    request = api_request(browser)

    try do
      result = seed_scenario(request, spec_dir, scenario, %{"RUN_ID" => run_id})
      outputs = result["outputs"]
      project_slug = get_in(outputs, ["projects", project_title]) || ""
      section_slug = get_in(outputs, ["sections", project_title]) || ""

      assert project_slug != "", "Scenario did not return the #{name} project slug"
      assert section_slug != "", "Scenario did not return the #{name} section slug"
      section_slug
    after
      Playwright.APIRequestContext.dispose(request)
    end
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
