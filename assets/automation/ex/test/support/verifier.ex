defmodule OliE2E.Verifier do
  @moduledoc "Port of src/core/verify/Verifier.ts."

  import ExUnit.Assertions

  alias Playwright.Expect

  def expect_is_visible(locator, description \\ "Should be visible."),
    do: locator |> Expect.message(description) |> Expect.to_be_visible!()

  def expect_is_hidden(locator, description \\ "Should be hidden."),
    do: locator |> Expect.message(description) |> Expect.to_be_hidden!()

  def expect_has_text(locator, expected_text, description \\ "Should have text:"),
    do:
      locator
      |> Expect.message("[#{description}] \"#{text(expected_text)}\"")
      |> Expect.to_have_text!(expected_text)

  def expect_contain_text(locator, expected_text, description \\ "Should contain text:"),
    do:
      locator
      |> Expect.message("[#{description}] \"#{text(expected_text)}\"")
      |> Expect.to_contain_text!(expected_text)

  def expect_has_class(locator, expected_class, description \\ "Should have class:"),
    do:
      locator
      |> Expect.message("[#{description}] \"#{expected_class}\"")
      |> Expect.to_have_class!(Regex.compile!("\\b#{expected_class}\\b"))

  def expect_not_has_class(locator, not_expected_class, description \\ "Should NOT have class:"),
    do:
      locator
      |> Expect.message("[#{description}] \"#{not_expected_class}\"")
      |> Expect.not_to_have_class!(Regex.compile!("\\b#{not_expected_class}\\b"))

  def expect_contain_class(locator, expected_class, description \\ "Should contain class:"),
    do:
      locator
      |> Expect.message("[#{description}] \"#{expected_class}\"")
      |> Expect.to_contain_class!(expected_class)

  def expect_not_contain_class(
        locator,
        forbidden_class,
        description \\ "Should NOT contain class:"
      ),
      do:
        locator
        |> Expect.message("[#{description}] \"#{forbidden_class}\"")
        |> Expect.not_to_contain_class!(forbidden_class)

  def expect_title(page, expected_title, description \\ "Page should have title:"),
    do:
      page
      |> Expect.message("[#{description}] \"#{text(expected_title)}\"")
      |> Expect.to_have_title!(expected_title)

  def expect_is_enabled(locator, description \\ "Should be enabled."),
    do: locator |> Expect.message(description) |> Expect.to_be_enabled!()

  def expect_is_disabled(locator, description \\ "Should be disabled."),
    do: locator |> Expect.message(description) |> Expect.to_be_disabled!()

  def expect_to_have_attribute(
        locator,
        attribute,
        value,
        description \\ "Should have attribute:"
      ),
      do:
        locator
        |> Expect.message("[#{description}] #{attribute}=\"#{text(value)}\"")
        |> Expect.to_have_attribute!(attribute, value)

  def expect_to_have_count(locator, count, description \\ "Should have a count of:"),
    do: locator |> Expect.message("[#{description}] #{count}") |> Expect.to_have_count!(count)

  def expect_to_have_value(locator, value, description \\ "Should have value:"),
    do:
      locator
      |> Expect.message("[#{description}] \"#{text(value)}\"")
      |> Expect.to_have_value!(value)

  def expect_is_attached(locator, description \\ "Element should be attached:"),
    do: locator |> Expect.message("[#{description}]") |> Expect.to_be_attached!()

  def expect_true(condition, description \\ "Expected value to be true"),
    do: assert(condition, description)

  def expect_false(condition, description \\ "Expected value to be false"),
    do: refute(condition, description)

  # A value in a JS template literal: a RegExp is `/source/`, an array joins with commas.
  defp text(%Regex{} = regex), do: "/#{Regex.source(regex)}/"
  defp text(values) when is_list(values), do: Enum.map_join(values, ",", &text/1)
  defp text(value), do: to_string(value)
end
