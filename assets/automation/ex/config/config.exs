import Config

# Runtime credentials and account links must never enter traces or screenshots
# (playwright.config.ts: `protectSecrets`).
protect_secrets? =
  System.get_env("CI") != nil or System.get_env("PLAYWRIGHT_SCENARIO_TOKEN") != nil or
    System.get_env("PLAYWRIGHT_CAPTCHA_TOKEN") != nil

# playwright.config.ts, with its one project ('Google Chrome') folded in.
config :playwright, :test,
  # The PR job's `--workers=2`.
  workers: 2,
  launch_options: [
    channel: "chrome",
    args: ["--start-maximized", "--ignore-certificate-errors", "--window-size=1920,1080"]
  ],
  base_url: System.get_env("PLAYWRIGHT_BASE_URL", "http://localhost"),
  ignore_https_errors: true,
  viewport: %{width: 1920, height: 1080},
  action_timeout: 15_000,
  trace: if(protect_secrets?, do: :off, else: :on),
  screenshot: if(protect_secrets?, do: :off, else: :on)

config :playwright, :expect, timeout: 10_000

# playwright_ex logs every API call (pw:api) at :debug.
config :logger, level: :warning
