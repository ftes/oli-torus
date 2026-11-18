defmodule OliE2E.Tasks.Home do
  @moduledoc """
  Port of src/systems/torus/tasks/HomeTask.ts.

  `getLoginData(role)` (a runtimeConfig global) is replaced by `login_data`, the
  `%{role_atom => record}` map of the spec's `setRuntimeConfig({loginData: ...})`; a
  record has the keys `type`, `page_title`, `role`, `welcome_text`, `welcome_title`,
  `email`, `pass` and optionally `header`, `name`, `last_name`.
  `logout` and the `@step` decorators are not ported (no @pr spec uses them).
  """

  alias OliE2E.{Utils, Waiter}
  alias OliE2E.Pom.{Login, Sidebar}
  alias Playwright.{Locator, Page}

  defstruct [:page, :environment, :login_data, :utils, :loginpo, :sidebar]

  def new(page, login_data \\ %{}, environment \\ "/") do
    %__MODULE__{
      page: page,
      environment: environment,
      login_data: login_data,
      utils: Utils.new(page),
      loginpo: Login.new(page),
      sidebar: Sidebar.new(page)
    }
  end

  def go_to_site(%{page: page} = po, environment \\ nil) do
    Page.goto!(page, environment || po.environment)
  end

  def close_site(%{page: page}), do: Page.close!(page)

  @doc "`role` is `:student`, `:instructor`, `:author` or `:administrator`."
  def login(%{page: page} = po, role) do
    data_user = Map.fetch!(po.login_data, role)

    Login.accept_cookies(po.loginpo)
    Utils.modal_disappears(po.utils)
    Login.select_role_account(po.loginpo, data_user.type)
    Waiter.wait_for_load_state(page)
    Page.wait_for_selector!(page, ".phx-connected", state: :attached)
    Login.verify_title(po.loginpo, data_user.page_title)
    Login.verify_role(po.loginpo, data_user.role)
    Login.verify_welcome_text(po.loginpo, data_user.welcome_text)
    Login.fill_email(po.loginpo, data_user.email)
    Login.fill_password(po.loginpo, data_user.pass)
    Login.click_sign_in_button(po.loginpo)
    Login.verify_welcome_title(po.loginpo, data_user.welcome_title)

    if role == :administrator, do: dismiss_flash_messages(po)
  end

  def enter_to_curriculum(po), do: menu_create(po, "Curriculum")

  def enter_to_course_author(po), do: Sidebar.click_in_menu(po.sidebar, "Course Author")

  def enter_to_overview(po), do: Sidebar.click_in_menu(po.sidebar, "Overview")

  def enter_to_publish(po), do: menu_publish(po, "Publish")

  def enter_to_learn(po), do: Sidebar.click_in_menu(po.sidebar, "Learn")

  def enter_to_products(po), do: menu_create(po, "Templates")

  def enter_to_bibliography(po), do: menu_create(po, "Bibliography")

  defp menu_create(po, menu) do
    unless Sidebar.is_visible(po.sidebar, menu) do
      Sidebar.click_in_menu(po.sidebar, "Create")
    end

    Sidebar.click_in_menu(po.sidebar, menu)
  end

  defp menu_publish(po, menu) do
    unless Sidebar.is_visible(po.sidebar, menu) do
      Sidebar.click_in_menu(po.sidebar, "PublishBTN")
    end

    Sidebar.click_in_menu(po.sidebar, menu)
  end

  defp dismiss_flash_messages(%{page: page}) do
    possible_flash =
      page
      |> Page.locator(
        ~s|#live_flash_container [role="alert"], #live_flash_container .alert, .alert[role="alert"], .alert-info, .alert-danger|
      )
      |> Locator.first()

    Enum.reduce_while(0..2, nil, fn _attempt, _ ->
      with :ok <- Locator.wait_for(possible_flash, state: :visible, timeout: 2000),
           {:ok, true} <- Locator.is_visible(possible_flash) do
        close_button =
          possible_flash
          |> Locator.locator(~s|button[aria-label="Close"], button.close, [data-bs-dismiss="alert"]|)
          |> Locator.first()

        if Locator.count!(close_button) > 0 do
          Locator.click!(close_button)
        else
          Locator.evaluate!(possible_flash, "(node) => node.remove()")
        end

        try do
          Waiter.wait_for(possible_flash, :hidden)
          {:cont, nil}
        rescue
          _ ->
            case Locator.wait_for(possible_flash, state: :hidden, timeout: 1000) do
              :ok -> {:cont, nil}
              _ -> {:halt, nil}
            end
        end
      else
        _ -> {:halt, nil}
      end
    end)

    :ok
  end
end
