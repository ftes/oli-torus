defmodule OliE2E.Pom.Sidebar do
  @moduledoc """
  Port of src/systems/torus/pom/home/SidebarCO.ts. Item names are the JS string
  literals (`"Course Author"`, `"Create"`, `"PublishBTN"`, ...).
  """

  alias OliE2E.Verifier
  alias Playwright.{Locator, Page}

  @button_names MapSet.new(["Minimize", "Expand", "Create", "PublishBTN", "Improve", "Support"])

  defstruct [:page]

  def new(page), do: %__MODULE__{page: page}

  def click_in_menu(po, name) do
    if button?(name) do
      click_by_role(po, :button, name)
    else
      click_by_role(po, :link, name)
    end
  end

  def is_visible(po, name) do
    if button?(name) do
      visible_by_role(po, :button, name)
    else
      visible_by_role(po, :link, name)
    end
  end

  defp button?(name), do: MapSet.member?(@button_names, name)

  defp click_by_role(po, role, name) do
    bl = create_locator(po, role, name)
    Verifier.expect_is_visible(bl)
    Locator.click!(bl)
  end

  defp visible_by_role(po, role, name) do
    bl = create_locator(po, role, name)
    Locator.is_visible!(bl)
  end

  defp create_locator(po, role, name) do
    names = aliases_for(name)

    found =
      Enum.find_value(sidebar_candidates(po), fn sidebar ->
        if visible?(sidebar) do
          Enum.find_value(names, fn sidebar_name ->
            item = Locator.get_by_role(sidebar, role, name: sidebar_name, exact: true)
            if count(item) > 0, do: item
          end)
        end
      end)

    found ||
      po
      |> sidebar_candidates()
      |> hd()
      |> Locator.get_by_role(role, name: hd(names), exact: true)
  end

  defp visible?(locator), do: match?({:ok, true}, Locator.is_visible(locator))

  defp count(locator) do
    case Locator.count(locator) do
      {:ok, n} -> n
      _ -> 0
    end
  end

  defp aliases_for("PublishBTN"), do: ["Publish"]
  defp aliases_for(name) when name in ["Products", "Templates"], do: ["Templates", "Products"]
  defp aliases_for(name), do: [name]

  defp sidebar_candidates(%{page: page}) do
    [
      page |> Page.locator("#desktop-workspace-nav-menu") |> Locator.first(),
      page |> Page.locator("#desktop-nav-menu") |> Locator.first(),
      page |> Page.locator("#mobile-nav-menu") |> Locator.first()
    ]
  end
end
