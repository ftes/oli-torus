defmodule OliE2E.Pom.Curriculum do
  @moduledoc """
  Port of src/systems/torus/pom/project/CurriculumPO.ts (the page-entry methods the @pr specs
  use; unit/module/import/delete helpers are not ported). `index` is `:first`, `:last` or an
  integer.
  """

  alias OliE2E.{Verifier, Waiter}
  alias Playwright.{Locator, Page, Promise}

  defstruct [
    :page,
    :content_center,
    :practice_button,
    :adaptive_simple_practice_button,
    :adaptive_practice_button,
    :scored_button,
    :edit_page_link
  ]

  def new(page) do
    %__MODULE__{
      page: page,
      content_center: Page.locator(page, "#content > div.container.mx-auto.p-8"),
      practice_button: Page.get_by_role(page, :button, name: "Practice"),
      adaptive_simple_practice_button:
        Page.get_by_role(page, :button, name: "Practice (Simple Author)"),
      adaptive_practice_button:
        Page.get_by_role(page, :button, name: "Practice (Advanced Author)"),
      scored_button: page |> Page.get_by_role(:button, name: "Scored") |> Locator.first(),
      edit_page_link: Page.get_by_role(page, :link, name: "Edit Page")
    }
  end

  def waiting_to_be_centered(po), do: Waiter.wait_for(po.content_center, :visible)

  def click_basic_practice_button(po) do
    po.practice_button |> Locator.first() |> Locator.click!()
    if page_editor_is_open(po), do: true, else: verify_not_opened(po, "New Page")
  end

  def click_basic_scored_button(po) do
    po.scored_button |> Locator.first() |> Locator.click!()
    if page_editor_is_open(po), do: true, else: verify_not_opened(po, "New Assessment")
  end

  def click_adaptive_practice_button(po) do
    Locator.click!(po.adaptive_practice_button)
    wait_for_adaptive_page_or_verify(po, "New Advanced Author Page")
  end

  def click_adaptive_simple_practice_button(po) do
    Locator.click!(po.adaptive_simple_practice_button)
    wait_for_adaptive_page_or_verify(po, "New Simple Author Page")
  end

  defp verify_not_opened(po, title) do
    verify_page(po, title, "Edit Page", :last)
    false
  end

  defp wait_for_adaptive_page_or_verify(po, title) do
    editor_title_bar = Page.locator(po.page, "div.TitleBar")

    try do
      Promise.race([
        Promise.async(fn ->
          Page.wait_for_url!(po.page, ~r{/curriculum/[^/]+/edit$}, timeout: 10_000)
        end),
        Promise.async(fn ->
          Locator.wait_for!(editor_title_bar, state: :visible, timeout: 10_000)
        end)
      ])
      |> Promise.await!()

      true
    rescue
      # fall through to the curriculum entry verification below
      _ ->
        verify_page(po, title, "Edit Page", :last)
        false
    end
  end

  def page_editor_is_open(po, timeout \\ 2000) do
    if page_editor_url?(po) do
      true
    else
      try do
        Page.wait_for_url!(po.page, ~r{/curriculum/[^/]+/edit$}, timeout: timeout)
        true
      rescue
        _ -> false
      end
    end
  end

  def click_edit_page_link(po, name, edit, index) do
    l = create_locator_page(po, name, edit, index)
    l |> Locator.locator(po.edit_page_link) |> Locator.click!()
  end

  def expect_page_visible(po, name, link \\ "Edit Page", index \\ :last),
    do: verify_page(po, name, link, index)

  defp verify_page(po, name, edit, index) do
    l = create_locator_page(po, name, edit, index)
    Verifier.expect_is_visible(l)
  end

  defp page_editor_url?(po), do: Regex.match?(~r{/curriculum/[^/]+/edit$}, Page.url(po.page))

  defp create_locator_page(%{page: page}, name, edit, index) do
    div = Page.locator(page, "div.curriculum-entry")
    span = Page.locator(page, ~s|span:has-text("#{name}")|)
    a = Page.locator(page, ~s|a:has-text("#{edit}")|)

    l =
      if name do
        div |> Locator.filter(has: span) |> Locator.filter(has: a)
      else
        Locator.filter(div, has: a)
      end

    all_l = Locator.all!(l)

    cond do
      length(all_l) == 1 -> l
      index == :first -> Locator.first(l)
      index == :last -> Locator.last(l)
      true -> Locator.nth(l, index)
    end
  end
end
