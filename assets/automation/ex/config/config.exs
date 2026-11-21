import Config

# An unset or empty variable is false, as JS's `Boolean(process.env.X)` and `||`.
set? = fn name -> System.get_env(name) not in [nil, ""] end

# Runtime credentials and account links must never enter traces or screenshots
# (playwright.config.ts: `protectSecrets`).
protect_secrets? =
  set?.("CI") or set?.("PLAYWRIGHT_SCENARIO_TOKEN") or set?.("PLAYWRIGHT_CAPTCHA_TOKEN")

# playwright.config.ts; its one project ('Google Chrome') is OliE2E.Case.projects/0.
config :playwright, :test,
  # playwright.config.ts's `workers: 1`, and the PR job's `--workers=2` on CI.
  workers: if(set?.("CI"), do: 2, else: 1),
  launch_options: [
    args: ["--start-maximized", "--ignore-certificate-errors", "--window-size=1920,1080"]
  ],
  base_url:
    if(set?.("PLAYWRIGHT_BASE_URL"),
      do: System.get_env("PLAYWRIGHT_BASE_URL"),
      else: "http://localhost"
    ),
  ignore_https_errors: true,
  action_timeout: 15_000,
  trace: if(protect_secrets?, do: :off, else: :on),
  screenshot: if(protect_secrets?, do: :off, else: :on)

config :playwright, :expect, timeout: 10_000

# playwright_ex logs every API call (pw:api) at :debug.
config :logger, level: :warning
