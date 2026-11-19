import Config

# An unset or empty variable is false, as JS's `Boolean(process.env.X)`.
set? = fn name -> System.get_env(name) not in [nil, ""] end

# Runtime credentials and account links must never enter traces or screenshots
# (playwright.config.ts: `protectSecrets`).
protect_secrets? =
  set?.("CI") or set?.("PLAYWRIGHT_SCENARIO_TOKEN") or set?.("PLAYWRIGHT_CAPTCHA_TOKEN")

# playwright.config.ts, with its one project ('Google Chrome') folded in.
config :playwright, :test,
  # playwright.config.ts's `workers: 1`, and the PR job's `--workers=2` on CI.
  workers: if(set?.("CI"), do: 2, else: 1),
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
