defmodule OliE2E.Verifier do
  @moduledoc """
  Port of src/core/verify/Verifier.ts.

  The `description` arguments (expect messages in JS) are accepted and ignored:
  the matchers have no `message:` option.
  """

  import ExUnit.Assertions

  alias Playwright.Expect

  def expect_is_visible(locator, _description \\ "Should be visible."), do: Expect.to_be_visible!(locator)

  def expect_is_hidden(locator, _description \\ "Should be hidden."), do: Expect.to_be_hidden!(locator)

  def expect_has_text(locator, expected_text, _description \\ "Should have text:"),
    do: Expect.to_have_text!(locator, expected_text)

  def expect_contain_text(locator, expected_text, _description \\ "Should contain text:"),
    do: Expect.to_contain_text!(locator, expected_text)

  def expect_has_class(locator, expected_class, _description \\ "Should have class:"),
    do: Expect.to_have_class!(locator, Regex.compile!("\\b#{expected_class}\\b"))

  def expect_not_has_class(locator, not_expected_class, _description \\ "Should NOT have class:"),
    do: Expect.not_to_have_class!(locator, Regex.compile!("\\b#{not_expected_class}\\b"))

  def expect_contain_class(locator, expected_class, _description \\ "Should contain class:"),
    do: Expect.to_contain_class!(locator, expected_class)

  def expect_not_contain_class(locator, forbidden_class, _description \\ "Should NOT contain class:"),
    do: Expect.not_to_contain_class!(locator, forbidden_class)

  def expect_title(page, expected_title, _description \\ "Page should have title:"),
    do: Expect.to_have_title!(page, expected_title)

  def expect_is_enabled(locator, _description \\ "Should be enabled."), do: Expect.to_be_enabled!(locator)

  def expect_is_disabled(locator, _description \\ "Should be disabled."), do: Expect.to_be_disabled!(locator)

  def expect_to_have_attribute(locator, attribute, value, _description \\ "Should have attribute:"),
    do: Expect.to_have_attribute!(locator, attribute, value)

  def expect_to_have_count(locator, count, _description \\ "Should have a count of:"),
    do: Expect.to_have_count!(locator, count)

  def expect_to_have_value(locator, value, _description \\ "Should have value:"),
    do: Expect.to_have_value!(locator, value)

  def expect_is_attached(locator, _description \\ "Element should be attached:"),
    do: Expect.to_be_attached!(locator)

  def expect_true(condition, description \\ "Expected value to be true"), do: assert(condition, description)

  def expect_false(condition, description \\ "Expected value to be false"), do: refute(condition, description)
end
