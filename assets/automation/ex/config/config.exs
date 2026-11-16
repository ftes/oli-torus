import Config

base_url = System.get_env("PLAYWRIGHT_BASE_URL", "http://localhost")
ci? = System.get_env("CI") != nil
protect_secrets? = ci? or System.get_env("PLAYWRIGHT_SCENARIO_TOKEN") != nil or System.get_env("PLAYWRIGHT_CAPTCHA_TOKEN") != nil

# Runtime credentials and account links must never enter traces or screenshots
# (playwright.config.ts: `protectSecrets`).
config :playwright, :test,
  browser_name: :chromium,
  workers: 2,
  launch_options: [
    channel: System.get_env("PW_CHANNEL", "chrome"),
    args: ["--start-maximized", "--ignore-certificate-errors", "--window-size=1920,1080"]
  ],
  context_options: [
    base_url: base_url,
    ignore_https_errors: true,
    viewport: %{width: 1920, height: 1080}
  ],
  action_timeout: 15_000,
  trace: if(protect_secrets?, do: :off, else: :on),
  screenshot: if(protect_secrets?, do: :off, else: :on)

config :playwright, :expect, timeout: 10_000

config :logger, level: :warning
