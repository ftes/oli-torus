defmodule OliE2E.Mailbox do
  @moduledoc "Port of src/core/mailbox.ts."

  alias Playwright.APIRequestContext
  alias Playwright.APIResponse

  @default_timeout_ms 30_000
  @poll_interval_ms 250

  def wait_for_email(request, options) do
    deadline = System.monotonic_time(:millisecond) + Keyword.get(options, :timeout_ms, @default_timeout_ms)
    loop(request, options, deadline)
  end

  defp loop(request, options, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      case list_emails(request, options) do
        [first | _] ->
          get_email(request, options, first["id"])

        [] ->
          Process.sleep(@poll_interval_ms)
          loop(request, options, deadline)
      end
    else
      raise "Timed out waiting for '#{options[:subject]}' email sent to '#{options[:recipient]}'."
    end
  end

  defp list_emails(request, options) do
    url =
      URI.merge(options[:base_url], "/test/emails")
      |> Map.put(:query, URI.encode_query(%{"to" => options[:recipient], "subject" => options[:subject]}))
      |> to_string()

    response = APIRequestContext.get!(request, url, headers: auth_headers(options[:token]))

    unless APIResponse.ok(response) do
      raise "Mailbox list request failed (#{APIResponse.status(response)})"
    end

    APIResponse.json!(response)["emails"]
  end

  defp get_email(request, options, id) do
    url = URI.merge(options[:base_url], "/test/emails/#{URI.encode_www_form(id)}") |> to_string()
    response = APIRequestContext.get!(request, url, headers: auth_headers(options[:token]))

    unless APIResponse.ok(response) do
      raise "Mailbox detail request failed (#{APIResponse.status(response)})"
    end

    APIResponse.json!(response)["email"]
  end

  defp auth_headers(token), do: %{"x-playwright-scenario-token" => token}

  @doc "segment: \"authors\" | \"users\"; action: \"confirm\" | \"reset_password\""
  def extract_account_link(html_body, text_body, segment, action) do
    path = "/#{segment}/#{action}/"
    source = [html_body, text_body] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
    regex = Regex.compile!("https?:\\/\\/[^\\s\"'<]+#{Regex.escape(path)}[^\\s\"'<]+")

    case Regex.run(regex, source) do
      [match | _] -> String.replace(match, "&amp;", "&")
      nil -> raise "Expected an account #{action} URL under #{path} in the email."
    end
  end
end
