defmodule OliE2E.Accessibility do
  @moduledoc "Port of src/core/accessibility.ts."

  import ExUnit.Assertions

  alias OliE2E.AxeBuilder
  alias Playwright.{Expect, Locator, Page}

  @focus_indicator_script """
  (element) => {
    const readStyles = () => {
      const computed = window.getComputedStyle(element);
      return {
        outline: {
          style: computed.outlineStyle,
          width: computed.outlineWidth,
          color: computed.outlineColor,
        },
        boxShadow: computed.boxShadow,
        borders: [
          {
            color: computed.borderTopColor,
            style: computed.borderTopStyle,
            width: computed.borderTopWidth,
          },
          {
            color: computed.borderRightColor,
            style: computed.borderRightStyle,
            width: computed.borderRightWidth,
          },
          {
            color: computed.borderBottomColor,
            style: computed.borderBottomStyle,
            width: computed.borderBottomWidth,
          },
          {
            color: computed.borderLeftColor,
            style: computed.borderLeftStyle,
            width: computed.borderLeftWidth,
          },
        ],
      };
    };

    const hasVisibleColor = (value) => {
      if (!value || value.toLowerCase() === 'transparent') return false;

      const alpha = value.match(/rgba?\\((?:[^,]+,){3}\\s*([^,)]+)/i)?.[1];
      return alpha === undefined || Number.parseFloat(alpha) > 0;
    };

    const hasVisibleBoxShadow = (value) =>
      value !== 'none' &&
      value.split(/,(?![^()]*\\))/).some((shadow) => {
        if (!hasVisibleColor(shadow)) return false;

        const dimensions = shadow
          .replace(/rgba?\\([^)]*\\)|hsla?\\([^)]*\\)|#[0-9a-f]+|\\b[a-z]+\\b/gi, '')
          .match(/-?(?:\\d+\\.?\\d*|\\.\\d+)/g);

        return dimensions?.some((dimension) => Number.parseFloat(dimension) !== 0) ?? false;
      });

    const originalTransition = element.style.getPropertyValue('transition');
    const originalTransitionPriority = element.style.getPropertyPriority('transition');
    element.style.setProperty('transition', 'none', 'important');

    const focusedStyles = readStyles();
    const wasFocused = document.activeElement === element;

    if (wasFocused) element.blur();
    const unfocusedStyles = readStyles();

    if (originalTransition) {
      element.style.setProperty('transition', originalTransition, originalTransitionPriority);
    } else {
      element.style.removeProperty('transition');
    }

    if (wasFocused) element.focus({ preventScroll: true });

    const hasOutline =
      focusedStyles.outline.style !== 'none' &&
      Number.parseFloat(focusedStyles.outline.width) > 0 &&
      hasVisibleColor(focusedStyles.outline.color);

    const hasBoxShadow = hasVisibleBoxShadow(focusedStyles.boxShadow);

    const hasBorderChange = focusedStyles.borders.some((focusedBorder, index) => {
      const unfocusedBorder = unfocusedStyles.borders[index];
      const hasVisibleBorder =
        Number.parseFloat(focusedBorder.width) > 0 && hasVisibleColor(focusedBorder.color);

      return (
        hasVisibleBorder &&
        (focusedBorder.color !== unfocusedBorder.color ||
          focusedBorder.style !== unfocusedBorder.style ||
          focusedBorder.width !== unfocusedBorder.width)
      );
    });

    return hasOutline || hasBoxShadow || hasBorderChange;
  }
  """

  @doc """
  Scan a connected, styled page after its finite loading animations settle.
  Options: `:exclude_cookie_consent` (default true), `:theme` (:light | :dark).
  """
  def scan_page_accessibility(page, page_name, options \\ []) do
    Page.wait_for_load_state!(page, :load)
    page |> Page.locator("[data-phx-main]") |> Expect.to_have_class!(~r/phx-connected/)
    page |> Page.locator("#nprogress") |> Expect.to_have_count!(0)

    Expect.poll!(
      fn ->
        page
        |> Page.locator(~s|link[rel="stylesheet"][href="/css/app.css"]|)
        |> Locator.evaluate!("(link) => Boolean(link.sheet?.cssRules.length)")
      end,
      &assert(&1 == true),
      message: "Tailwind CSS must be loaded before scanning accessibility"
    )

    Expect.poll!(
      fn ->
        Page.evaluate!(page, """
        () =>
          document.fonts.status === 'loaded' &&
          document
            .getAnimations()
            .every(
              (animation) =>
                animation.playState !== 'running' ||
                animation.effect?.getComputedTiming().iterations === Infinity,
            )
        """)
      end,
      &assert(&1 == true),
      message: "Page fonts and finite animations must settle before scanning accessibility",
      timeout: 10_000
    )

    builder = AxeBuilder.new(page) |> AxeBuilder.with_tags(["wcag2a", "wcag2aa", "wcag412"])

    builder =
      if Keyword.get(options, :exclude_cookie_consent, true),
        do: AxeBuilder.exclude(builder, "#cookie_consent_display"),
        else: builder

    results = AxeBuilder.analyze!(builder)

    case results["violations"] do
      [] ->
        :ok

      violations ->
        details =
          Enum.map_join(violations, "\n", fn violation ->
            nodes =
              Enum.map_join(violation["nodes"], "; ", fn node ->
                Enum.join(node["target"], ", ")
              end)

            "#{violation["id"]} (#{violation["impact"] || "unknown"}): #{violation["help"]} [#{nodes}]"
          end)

        raise "Accessibility violations on #{page_name} (#{Keyword.get(options, :theme, :light)}):\n#{details}"
    end
  end

  def set_accessibility_theme(page, theme) when theme in [:dark, :light] do
    Page.evaluate!(
      page,
      "(nextTheme) => { localStorage.setItem('theme', nextTheme); }",
      Atom.to_string(theme)
    )

    Page.reload!(page, wait_until: :load)
  end

  def expect_keyboard_focus(page, selector) do
    target = page |> Page.locator(selector) |> Locator.filter(visible: true) |> Locator.first()
    Expect.to_be_visible!(target)
    Locator.focus!(target)
    Expect.to_be_focused!(target)
    page |> Page.keyboard() |> Playwright.Keyboard.press!("Tab")

    focused = Page.locator(page, ":focus-visible")
    Expect.to_have_count!(focused, 1)
    Expect.to_be_visible!(focused)

    has_visible_focus_indicator = Locator.evaluate!(focused, @focus_indicator_script)

    assert has_visible_focus_indicator == true
  end
end
