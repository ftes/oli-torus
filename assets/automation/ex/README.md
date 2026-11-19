# ExUnit port of the @pr suite

An ExUnit port, with [playwright_ex](https://hexdocs.pm/playwright_ex), of the JS specs tagged
`@pr` (see `.github/workflows/pr-playwright-ex.yml`). It is a separate Mix project, run next to
the JS suite: each test module mirrors one `test.describe` of a JS spec, `test/support` mirrors
the JS page objects and tasks, and the scenario YAMLs are read from the JS `tests` tree.

## Running it

Start a Torus server in `MIX_ENV=playwright` (see `.github/workflows/pr-playwright.yml` for the
environment), then:

```bash
cd assets/automation && npm ci   # the axe-core used by the accessibility tests
cd ex
mix deps.get
mix playwright.install chrome    # once, and after upgrading playwright_ex
PLAYWRIGHT_BASE_URL=http://localhost:4002 \
PLAYWRIGHT_SCENARIO_TOKEN=... PLAYWRIGHT_CAPTCHA_TOKEN=... \
mix test --only pr
```

The tokens must match the server's. `mix test --failed` reruns the failures. Each test writes
its traces and screenshots to `test-results/` (both off in CI and when a token is set, as in
`playwright.config.ts`); open a trace with `mix playwright.cli show-trace <path>`.

## Porting a spec

- A `test.describe` is a module using `OliE2E.Case`, tagged `@moduletag :pr` when its title
  has `@pr`.
- A `test.describe.serial` whose tests depend on each other is one test with a
  `Playwright.Test.step` per JS test, getting each step's page from `OliE2E.Case.next_page/2`.
  ExUnit has no serial mode, and `mix test --failed` reruns a test with a fresh `setup_all`.
- `beforeAll` is `setup_all`, `test.setTimeout` is `@tag timeout:`, and the `@step` decorator is
  `Playwright.Test.step`.
