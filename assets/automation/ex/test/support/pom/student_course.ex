defmodule OliE2E.Pom.StudentCourse do
  @moduledoc """
  Port of src/systems/torus/pom/course/StudentCoursePO.ts.

  `isVisible({timeout})` is called without the timeout (JS ignores it).
  """

  alias OliE2E.Verifier
  alias Playwright.{Expect, Locator, Page, Promise}

  defstruct [:page, :course_home_markers, :view_selector, :onboarding_wizard]

  def new(page) do
    %__MODULE__{
      page: page,
      course_home_markers: [
        Page.locator(page, "#home-continue-learning"),
        Page.locator(page, "#home-assignments"),
        Page.locator(page, "#view_selector")
      ],
      view_selector: Page.locator(page, "#view_selector"),
      onboarding_wizard: Page.locator(page, "#student-onboarding-wizard")
    }
  end

  def present_assignment_block(po) do
    course_home = find_visible_course_home(po, 10_000)

    unless course_home do
      Verifier.expect_is_visible(hd(po.course_home_markers))
    end
  end

  def present_view_selector(po), do: Verifier.expect_is_visible(po.view_selector)

  def present_page(po, page_name) do
    l = Page.get_by_role(po.page, :heading, name: page_name, exact: true, level: 5)
    Verifier.expect_is_visible(l)
  end

  def course_content_ready(po, page_name) do
    po
    |> gallery_title(page_name)
    |> Locator.or_(outline_title(po, page_name))
    |> Locator.or_(po |> expand_toggles() |> Locator.first())
  end

  def open_page(%{page: page} = po, page_name) do
    gallery_title = gallery_title(po, page_name)

    gallery_card =
      page
      |> Page.locator(~s|div[phx-click="navigate_to_resource"]|)
      |> Locator.filter(has: gallery_title)
      |> Locator.first()

    outline_title = outline_title(po, page_name)

    grouped_outline_link =
      page
      |> Page.locator("a")
      |> Locator.filter(
        has:
          page
          |> Page.locator(~s|div[data-role="group-item"]|)
          |> Locator.filter(has_text: page_name)
      )
      |> Locator.first()

    po |> course_content_ready(page_name) |> Locator.first() |> Expect.to_be_visible!()

    if Locator.is_visible!(gallery_title) do
      click_and_wait_for_lesson(page, fn -> Locator.click!(gallery_card, force: true) end)
    else
      expand_collapsed_page_groups(po)

      # The course outline can render pages either as direct buttons or as links
      # nested inside an expanded grouped schedule item.
      if match?({:ok, true}, Locator.is_visible(outline_title)) do
        click_and_wait_for_lesson(page, fn -> Locator.click!(outline_title, force: true) end)
      else
        Verifier.expect_is_visible(grouped_outline_link)
        click_and_wait_for_lesson(page, fn -> Locator.click!(grouped_outline_link, force: true) end)
      end
    end

    Verifier.expect_is_visible(opened_page_title(po, page_name))
  end

  def open_first_page(%{page: page} = po, page_name) do
    start_course = Page.get_by_role(page, :link, name: "Start course", exact: true)
    page_entry = Page.get_by_text(page, page_name, exact: true)

    start_course |> Locator.or_(page_entry) |> Locator.first() |> Verifier.expect_is_visible()

    if match?({:ok, true}, Locator.is_visible(start_course)) do
      click_and_wait_for_lesson(page, fn -> Locator.click!(start_course) end)
      Verifier.expect_is_visible(opened_page_title(po, page_name))
    else
      open_page(po, page_name)
    end
  end

  def open_first_available_lesson(%{page: page}) do
    start_course = Page.get_by_role(page, :link, name: "Start course", exact: true)

    Verifier.expect_is_visible(start_course)
    click_and_wait_for_lesson(page, fn -> Locator.click!(start_course) end)
  end

  # `Promise.all([page.waitForURL(isStudentLessonPath, {timeout: 15000}), click])`
  defp click_and_wait_for_lesson(page, click) do
    Promise.all([
      Promise.async(fn -> Page.wait_for_url!(page, fn url -> student_lesson_path?(url.path) end, timeout: 15_000) end),
      Promise.async(click)
    ])
    |> Promise.await!()
  end

  # The title of an opened page. Basic pages render it as a heading. The adaptive
  # lesson header renders it as plain text after a screen-reader "Title:" prefix.
  defp opened_page_title(%{page: page}, page_name) do
    adaptive_header_title =
      page
      |> Page.locator("#delivery-header .lessonTitle")
      |> Locator.filter(has_text: Regex.compile!("(^|\\s)#{escape_reg_exp(page_name)}$"))

    page
    |> Page.get_by_role(:heading, name: page_name, exact: true)
    |> Locator.or_(adaptive_header_title)
    |> Locator.first()
  end

  defp gallery_title(%{page: page}, page_name) do
    Page.get_by_role(page, :heading, name: page_name, exact: true, level: 5)
  end

  defp outline_title(%{page: page}, page_name) do
    page
    |> Page.locator("button")
    |> Locator.filter(has: Page.get_by_text(page, page_name, exact: true))
    |> Locator.first()
  end

  defp expand_toggles(%{page: page}), do: Page.locator(page, ~s|button[phx-click="expand_item"]|)

  defp expand_collapsed_page_groups(po) do
    group_toggles = expand_toggles(po)
    count = Locator.count!(group_toggles)

    for index <- 0..(count - 1)//1 do
      toggle = Locator.nth(group_toggles, index)

      if match?({:ok, true}, Locator.is_visible(toggle)) do
        Locator.scroll_into_view_if_needed(toggle)
        Locator.click(toggle, force: true)
      end
    end

    :ok
  end

  def go_to_course_if_prompted(%{page: page} = po) do
    unless course_home_is_visible(po, 1000) do
      wizard_visible = match?({:ok, true}, Locator.is_visible(po.onboarding_wizard))

      if wizard_visible do
        reached =
          Enum.any?(1..3, fn _attempt ->
            (click_wizard_button(po, ~r/^Go to course$/i) and wait_for_course_home(po, 8000)) or
              (click_wizard_button(po, ~r/start survey|let's begin|continue|next/i) and
                 wait_for_course_home(po, 5000))
          end)

        unless reached do
          course_url = course_url_from_welcome(po)

          if course_url do
            Page.goto!(page, course_url, wait_until: :domcontentloaded)
            wait_for_course_home(po, 15_000)
          end
        end
      end
    end

    :ok
  end

  def enroll_if_prompted(%{page: page}) do
    enroll_button = Page.get_by_role(page, :button, name: "Enroll", exact: true)

    if match?({:ok, true}, Locator.is_visible(enroll_button)) do
      current_url = Page.url(page)

      Promise.all([
        Promise.async(fn ->
          try do
            Page.wait_for_url!(page, fn url -> URI.to_string(url) != current_url end, timeout: 15_000)
          rescue
            _ -> nil
          end
        end),
        Promise.async(fn -> Locator.click!(enroll_button) end)
      ])
      |> Promise.await!()

      recaptcha_error = Page.get_by_text(page, ~r/ReCaptcha failed|reCAPTCHA failed/i)

      if match?({:ok, true}, Locator.is_visible(recaptcha_error)) do
        raise "Enrollment captcha was rejected. Run this suite against a MIX_ENV=playwright build."
      end
    end

    :ok
  end

  defp click_wizard_button(po, name) do
    button = po.onboarding_wizard |> Locator.get_by_role(:button, name: name) |> Locator.last()

    if match?({:ok, true}, Locator.is_visible(button)) do
      Locator.scroll_into_view_if_needed(button)
      Locator.click(button, timeout: 5000, force: true)
      true
    else
      false
    end
  end

  defp wait_for_course_home(%{page: page} = po, timeout) do
    reached =
      Promise.race([
        Promise.async(fn ->
          match?(
            :ok,
            Page.wait_for_url(page, fn url -> not String.ends_with?(url.path || "", "/welcome") end, timeout: timeout)
          )
        end),
        Promise.async(fn -> course_home_is_visible(po, timeout) end)
      ])
      |> Promise.await!()

    if reached, do: course_home_is_visible(po, timeout), else: false
  end

  defp course_home_is_visible(po, timeout), do: find_visible_course_home(po, timeout) != nil

  defp find_visible_course_home(po, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_find_visible_course_home(po, deadline)
  end

  defp do_find_visible_course_home(po, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      marker = Enum.find(po.course_home_markers, &match?({:ok, true}, Locator.is_visible(&1)))

      if marker do
        marker
      else
        Page.wait_for_timeout!(po.page, 100)
        do_find_visible_course_home(po, deadline)
      end
    end
  end

  defp course_url_from_welcome(%{page: page}) do
    url = URI.parse(Page.url(page))

    if String.ends_with?(url.path || "", "/welcome") do
      URI.to_string(%{url | path: String.replace(url.path, ~r{/welcome$}, ""), query: nil})
    end
  end

  defp student_lesson_path?(pathname) do
    pathname = pathname || ""

    String.contains?(pathname, "/lesson/") or String.contains?(pathname, "/adaptive_lesson/") or
      String.contains?(pathname, "/prologue/")
  end

  defp escape_reg_exp(value), do: Regex.replace(~r/[.*+?^${}()|\[\]\\]/, value, "\\\\\\0")
end
