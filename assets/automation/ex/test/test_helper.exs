Logger.configure(level: :warning)
ExUnit.start(timeout: 60_000, exclude: [:skip])
