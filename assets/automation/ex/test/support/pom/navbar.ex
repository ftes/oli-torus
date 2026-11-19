defmodule OliE2E.Pom.Navbar do
  @moduledoc "Port of src/systems/torus/pom/home/NavbarCO.ts (only the methods the @pr specs use)."

  alias Playwright.{Locator, Page}

  defstruct [
    :page,
    :logo_link_navbar,
    :logo_link_header,
    :instructors_link,
    :authors_link,
    :support_link
  ]

  def new(page) do
    navigation = Page.get_by_role(page, :navigation)

    %__MODULE__{
      page: page,
      logo_link_navbar: Page.locator(page, "nav  a.navbar-brand"),
      logo_link_header: Page.locator(page, "#header_logo_button"),
      instructors_link: Locator.get_by_role(navigation, :link, name: "For Instructors"),
      authors_link: Locator.get_by_role(navigation, :link, name: "For Course Authors"),
      support_link: Page.locator(page, "#tech_support_navbar_sign_in")
    }
  end

  def click_logo(po) do
    Locator.click!(po.logo_link_navbar)
  rescue
    _ -> Locator.click!(po.logo_link_header)
  end

  def go_to_instructors_login(po), do: Locator.click!(po.instructors_link)

  def go_to_authors_login(po), do: Locator.click!(po.authors_link)

  def open_support_modal(po), do: Locator.click!(po.support_link)
end
