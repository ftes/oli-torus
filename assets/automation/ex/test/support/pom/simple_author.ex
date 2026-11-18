defmodule OliE2E.Pom.SimpleAuthor do
  @moduledoc """
  Port of src/systems/torus/pom/page/SimpleAuthorPO.ts (only the methods the specs and
  SimpleAuthorTask use).

  Page object for the adaptive Simple Author (flowchart-mode) editor.

  Simple Author has no "All changes saved" indicator: screen edits are
  debounced and persisted through `/api/v1/storage/...` and page edits
  through `/api/v1/project/.../resource/...`. `wait_for_saves` tracks those
  requests so callers can reload only after every pending write succeeded.

  Property-panel inputs carry generated ids such as
  `component_part_<rand>_<partId>_custom_<field>`; the stable part is the
  field suffix, so fields are located by `[id$="_<suffix>"]` inside the
  active tab.

  The PO's mutable fields (`pendingSaves`, `failedSaves`, `lastSaveActivity`) live in an
  `Agent`: the `page.on` listeners run in their own process.
  """

  alias OliE2E.Pom.BasicPracticePage
  alias Playwright.{Expect, Keyboard, Locator, Page, Promise, Request, Response}

  defstruct [:page, :state, :page_po]

  @save_request ~r{/api/v1/(storage/project/[^/]+/resource|project/[^/]+/(resource|activity))}
  # Longer than the editor's 500ms save debounce, so a pending write always shows up.
  @save_quiet_ms 800

  def new(page) do
    # { pending: Set<Request> (by guid), failed: string[], last: lastSaveActivity }
    {:ok, state} = Agent.start_link(fn -> %{pending: MapSet.new(), failed: [], last: 0} end)
    page_po = BasicPracticePage.new(page)

    Page.on(page, :request, fn request ->
      if save_request?(request) do
        Agent.update(state, fn s ->
          %{s | pending: MapSet.put(s.pending, request.guid), last: now()}
        end)
      end
    end)

    Page.on(page, :response, fn response ->
      request = Response.request(response)

      Agent.update(state, fn s ->
        if MapSet.member?(s.pending, request.guid) and not Response.ok(response) do
          failure =
            "#{Request.method(request)} #{Request.url(request)}: HTTP #{Response.status(response)} #{Response.status_text(response)}"

          %{s | failed: s.failed ++ [failure]}
        else
          s
        end
      end)
    end)

    Page.on(page, :request_finished, fn request -> settle(state, request) end)

    Page.on(page, :request_failed, fn request ->
      Agent.update(state, fn s ->
        if MapSet.member?(s.pending, request.guid) do
          error_text =
            case Request.failure(request) do
              %{errorText: text} -> text
              _ -> "network failure"
            end

          %{s | failed: s.failed ++ ["#{Request.method(request)} #{Request.url(request)}: #{error_text}"]}
        else
          s
        end
      end)

      settle(state, request)
    end)

    %__MODULE__{page: page, state: state, page_po: page_po}
  end

  defp settle(state, request) do
    Agent.update(state, fn s ->
      if MapSet.member?(s.pending, request.guid) do
        %{s | pending: MapSet.delete(s.pending, request.guid), last: now()}
      else
        s
      end
    end)
  end

  defp save_request?(request) do
    Request.method(request) in ["PUT", "POST"] and Regex.match?(@save_request, Request.url(request))
  end

  defp now, do: System.os_time(:millisecond)

  # ------------------------------------------------------------ locators

  defp stage(po), do: Page.locator(po.page, "section.aa-stage")
  defp component_toolbar(po), do: Page.locator(po.page, "#advanced-authoring .component-toolbar")
  defp screen_list(po), do: Page.locator(po.page, ".screen-list-container ul.screen-list")
  defp right_panel(po), do: Page.locator(po.page, ".fixed-right-panel")
  defp flowchart_sidebar(po), do: Page.locator(po.page, ".flowchart-sidebar")
  defp flowchart_nodes(po), do: Page.locator(po.page, ".flowchart-node")

  # ------------------------------------------------------------ persistence

  @doc """
  Waits until no Simple Author write is in flight and none started for a quiet
  window. The window is measured from the call too, so a write still inside
  the editor's 500ms save debounce is not missed.
  Throws immediately when a tracked save has a network error or unsuccessful
  HTTP response. Failures remain recorded for subsequent calls too.
  """
  def wait_for_saves(po, timeout \\ 30_000) do
    called_at = now()
    deadline = called_at + timeout
    do_wait_for_saves(po, called_at, deadline, timeout)
  end

  defp do_wait_for_saves(po, called_at, deadline, timeout) do
    if now() < deadline do
      assert_saves_succeeded(po)
      %{pending: pending, last: last} = Agent.get(po.state, & &1)
      quiet_for = now() - max(last, called_at)

      if MapSet.size(pending) == 0 and quiet_for >= @save_quiet_ms do
        :ok
      else
        Page.wait_for_timeout!(po.page, 250)
        do_wait_for_saves(po, called_at, deadline, timeout)
      end
    else
      assert_saves_succeeded(po)
      pending = Agent.get(po.state, &MapSet.size(&1.pending))
      raise "Simple Author saves did not settle within #{timeout}ms (#{pending} pending)"
    end
  end

  defp assert_saves_succeeded(po) do
    case Agent.get(po.state, & &1.failed) do
      [] -> :ok
      failed -> raise "Simple Author save failed:\n#{Enum.join(failed, "\n")}"
    end
  end

  @doc "Reloads the editor after pending writes settle and returns to the Screen Panel."
  def reload_editor(po) do
    wait_for_saves(po)
    Page.reload!(po.page)
    wait_for_editor_loaded(po)
  end

  @doc """
  Waits for the editor and leaves it editable: a reopened lesson can start in
  read-only mode. Once the editor header renders, the onboarding wizard is not
  showing, so only the read-only toggle needs handling.
  """
  def wait_for_editor_loaded(po) do
    po
    |> mode_header("Flowchart")
    |> Expect.message("Simple Author editor should load")
    |> Expect.to_be_visible!(timeout: 60_000)

    BasicPracticePage.disable_adaptive_read_only(po.page_po)

    Page.wait_for_function!(po.page, "() => customElements.get('janus-mcq') != null", nil, timeout: 30_000)
  end

  # ------------------------------------------------------------ modes

  def switch_to_screen_panel(po) do
    po |> mode_header("Screen Panel") |> Locator.click!()
    Expect.to_be_visible!(component_toolbar(po), timeout: 30_000)
    Expect.to_be_visible!(screen_list(po), timeout: 30_000)
  end

  def switch_to_flowchart(po) do
    po |> mode_header("Flowchart") |> Locator.click!()
    Expect.to_be_visible!(Locator.first(flowchart_nodes(po)), timeout: 30_000)
  end

  defp mode_header(po, name) do
    po.page
    |> Page.locator(".sidebar-header")
    |> Locator.filter(has: Page.locator(po.page, ".title", has_text: ~r/^#{name}$/))
    |> Locator.first()
  end

  # ------------------------------------------------------------ screens

  @doc """
  Adds a screen from the Screen Panel "Add new screen" dialog; the new screen
  becomes active.

  Creating the first screen after a load can re-render the editor and drop the
  dialog without creating anything. Retry once when no screen-creation request
  is observed within 15 seconds; an observed request is never retried. Assert
  a unique screen before using it and again after the initial saves settle.
  """
  def add_screen(po, title, type) do
    modal = Page.locator(po.page, ".add-screen-modal")

    {attempts, creation_observed} =
      Enum.reduce_while(0..1, {0, false}, fn _attempt, {attempts, _observed} ->
        attempts = attempts + 1
        po.page |> Page.get_by_role(:button, name: "Add new screen") |> Locator.click!()
        Expect.to_be_visible!(modal)
        modal |> Locator.locator("input.title-input") |> Locator.fill!(title)

        type_button =
          Locator.locator(modal, "button.screen-type", has_text: ~r/^#{escape_reg_exp(type)}$/)

        Locator.click!(type_button)
        Expect.to_have_class!(type_button, ~r/active/)

        creation_request =
          Page.wait_for_request(
            po.page,
            fn request ->
              Request.method(request) == "POST" and
                Regex.match?(~r{/api/v1/project/[^/]+/activity/}, Request.url(request))
            end,
            timeout: 15_000
          )

        modal |> Locator.get_by_role(:button, name: "Next") |> Locator.click!()

        case Promise.await(creation_request) do
          {:ok, _request} ->
            {:halt, {attempts, true}}

          {:error, %Playwright.TimeoutError{}} ->
            if match?({:ok, true}, Locator.is_visible(modal)), do: Keyboard.press!(Page.keyboard(po.page), "Escape")
            Expect.to_be_hidden!(modal)
            {:cont, {attempts, false}}

          {:error, error} ->
            raise error
        end
      end)

    assert_saves_succeeded(po)

    unless creation_observed do
      raise "Simple Author screen \"#{title}\": no creation POST observed after #{attempts} attempts (15s per attempt)"
    end

    unique_screen_message =
      "Simple Author screen \"#{title}\": expected exactly one screen after #{attempts} creation attempts"

    po
    |> screen_list_item(title)
    |> Expect.message(unique_screen_message)
    |> Expect.to_have_count!(1, timeout: 30_000)

    Expect.to_be_visible!(screen_list_item(po, title), timeout: 30_000)
    Expect.to_be_hidden!(modal, timeout: 30_000)
    # The new screen's initial save must land before edits, or the two
    # concurrent writes can persist the template over the edit.
    wait_for_saves(po)

    po
    |> screen_list_item(title)
    |> Expect.message(unique_screen_message)
    |> Expect.to_have_count!(1)

    expect_active_screen(po, title)
  end

  def select_screen(po, title) do
    po |> screen_list_item(title) |> Locator.click!()
    expect_active_screen(po, title)
  end

  defp expect_active_screen(po, title) do
    po |> screen_list() |> Locator.locator("li.active") |> Expect.to_have_text!(title, timeout: 30_000)
    po |> stage() |> Locator.locator("oli-adaptive-authoring") |> Expect.to_be_visible!(timeout: 30_000)
  end

  defp screen_list_item(po, title) do
    po
    |> screen_list()
    |> Locator.locator("li")
    |> Locator.filter(has_text: ~r/^#{escape_reg_exp(title)}$/)
  end

  # ------------------------------------------------------------ stage parts

  def part(po, part_id), do: po |> stage() |> Locator.locator(~s|[id="#{part_id}"]|)

  def parts_of_type(po, type), do: po |> stage() |> Locator.locator(type)

  def part_ids(po, type) do
    po |> parts_of_type(type) |> Locator.evaluate_all!("elements => elements.map((e) => e.id)")
  end

  def select_part(po, part_id) do
    part = part(po, part_id)
    Expect.to_be_visible!(part, timeout: 30_000)
    Locator.click!(part)
    Expect.to_have_attribute!(tab(po, "Component"), "aria-selected", "true", timeout: 10_000)
  end

  @doc """
  Clicks a toolbar component button and returns the id of the part it added.

  Right after a screen is created the toolbar can drop the first click, so the
  click is retried, but only while the screen still has no new part. That way a
  slow add is never doubled.
  """
  def add_component(po, component) do
    element_type = String.replace(component, "_", "-")
    before = part_ids(po, element_type)
    button = component_button(po, component)
    Expect.to_be_enabled!(button, timeout: 30_000)

    Enum.reduce_while(0..2, nil, fn _attempt, _ ->
      Locator.click!(button)

      added =
        po
        |> parts_of_type(element_type)
        |> Expect.to_have_count(length(before) + 1, timeout: 5_000) == :ok

      if added, do: {:halt, nil}, else: {:cont, nil}
    end)

    Expect.to_have_count!(parts_of_type(po, element_type), length(before) + 1)
    after_ids = part_ids(po, element_type)
    added = Enum.find(after_ids, fn id -> id not in before end)
    unless added, do: raise("A new #{element_type} part should be added")
    wait_for_saves(po)
    added
  end

  defp component_button(po, component) do
    po
    |> component_toolbar()
    |> Locator.locator(~s|button.component-button[data-component="#{component}"]|)
  end

  @doc "Opens the inline text configuration modal for a text-flow part and replaces its text."
  def set_text_flow_text(po, part_id, text) do
    select_part(po, part_id)
    po |> selection_toolbar_button("Edit") |> Locator.click!()

    modal = Page.locator(po.page, ".config-modal")
    editor = Locator.locator(modal, ".ql-editor")
    Expect.to_be_visible!(editor, timeout: 15_000)
    Locator.click!(editor)
    keyboard = Page.keyboard(po.page)
    Keyboard.press!(keyboard, "ControlOrMeta+A")
    Keyboard.type!(keyboard, text)
    Expect.to_have_text!(editor, text)
    modal |> Locator.get_by_role(:button, name: "Save") |> Locator.click!()
    Expect.to_be_hidden!(modal, timeout: 15_000)
    po |> part(part_id) |> Expect.to_contain_text!(text, timeout: 15_000)
    wait_for_saves(po)
  end

  defp selection_toolbar_button(po, title) do
    po.page
    |> Page.locator(~s|.active-selection-toolbar button[title="#{title}"]|)
    |> Locator.first()
  end

  # ------------------------------------------------------------ property panel

  defp tab(po, name), do: po |> right_panel() |> Locator.get_by_role(:tab, name: name, exact: true)

  def open_tab(po, name) do
    po |> tab(name) |> Locator.click!()
    po |> tab(name) |> Expect.to_have_attribute!("aria-selected", "true")
  end

  @doc "The content of the active right-panel tab."
  def tab_panel(po), do: po |> right_panel() |> Locator.locator(".tab-pane.active")

  def field(po, suffix) do
    po |> tab_panel() |> Locator.locator(~s|[id$="_#{suffix}"]|) |> Locator.first()
  end

  @doc """
  Fills a property field, blurs it (Lesson and Screen tabs only commit on
  blur), and waits for the write: quick successive edits can otherwise
  persist an older form state over a newer one.
  """
  def fill_field(po, suffix, value) do
    input = field(po, suffix)
    Expect.to_be_visible!(input)
    Locator.fill!(input, value)
    Locator.blur!(input)
    Expect.to_have_value!(input, value)
    wait_for_saves(po)
  end

  def select_field(po, suffix, value) do
    select = field(po, suffix)
    Expect.to_be_visible!(select)
    Locator.select_option!(select, value)
    Locator.blur!(select)
    Expect.to_have_value!(select, value)
    wait_for_saves(po)
  end

  def set_checkbox(po, suffix, checked) do
    checkbox = field(po, suffix)
    Expect.to_be_visible!(checkbox)
    Locator.set_checked!(checkbox, checked)
    Expect.to_be_checked!(checkbox, checked: checked)
    wait_for_saves(po)
  end

  def set_mcq_correct_answer(po, option_label) do
    po |> mcq_correct_answer_select() |> Locator.select_option!(%{label: option_label})
    wait_for_saves(po)
  end

  def set_mcq_correct_option(po, option_label, correct) do
    po |> mcq_correct_answer_checkbox(option_label) |> Locator.set_checked!(correct)
    wait_for_saves(po)
  end

  def add_hub_spoke(po, spoke_label) do
    po |> tab_panel() |> Locator.get_by_role(:button, name: "+ Add Spoke") |> Locator.click!()
    po |> tab_panel() |> Expect.to_contain_text!(spoke_label)
    wait_for_saves(po)
  end

  @doc ~S|The "Correct Answer" select of a single-selection MCQ.|
  def mcq_correct_answer_select(po) do
    po |> tab_panel() |> Locator.locator(~s|label:text-is("Correct Answer") + select|)
  end

  @doc "The per-option \"Correct Answer\" checkboxes of a multiple-selection MCQ."
  def mcq_correct_answer_checkbox(po, option_label) do
    po
    |> tab_panel()
    |> Locator.locator(~s|label.form-label:text-is("Correct Answer") ~ div|)
    |> Locator.filter(has_text: ~r/#{escape_reg_exp(option_label)}$/)
    |> Locator.locator(~s|input[type="checkbox"]|)
  end

  def set_part_width(po, part_id, width) do
    select_part(po, part_id)
    select = field(po, "Size_responsiveLayoutWidth")
    Expect.to_be_visible!(select)
    Locator.select_option!(select, %{label: width})

    Expect.to_have_class!(
      responsive_item(po, part_id),
      if(width == "100%", do: ~r/full-width/, else: ~r/half-width/),
      timeout: 10_000
    )

    wait_for_saves(po)
  end

  defp responsive_item(po, part_id) do
    po |> stage() |> Locator.locator(~s|.responsive-item[data-part-id="#{part_id}"]|)
  end

  @doc ~S|Chooses a media source through the "External URL" tab of the media picker.|
  def set_media_url(po, picker_label, url) do
    po |> tab_panel() |> Locator.get_by_role(:button, name: picker_label) |> Locator.click!()

    modal =
      po.page |> Page.locator(".modal") |> Locator.filter(has_text: picker_label) |> Locator.last()

    Expect.to_be_visible!(modal)
    modal |> Locator.get_by_role(:button, name: "External URL") |> Locator.click!()
    input = Locator.get_by_placeholder(modal, "Enter the media URL address")
    Locator.fill!(input, url)
    modal |> Locator.get_by_role(:button, name: "OK", exact: true) |> Locator.click!()
    Expect.to_be_hidden!(modal)
    po |> tab_panel() |> Expect.to_contain_text!(url)
    wait_for_saves(po)
  end

  def slider_feedback_rules(po) do
    po |> tab_panel() |> Locator.locator(".advanced-number-feedback")
  end

  def add_slider_feedback_rule(po, operator, values, feedback) do
    rules = slider_feedback_rules(po)
    count = Locator.count!(rules)
    po |> tab_panel() |> Locator.get_by_role(:button, name: "+ Add new feedback") |> Locator.click!()
    Expect.to_have_count!(rules, count + 1)

    rule = Locator.nth(rules, count)
    rule |> Locator.locator("select") |> Locator.select_option!(%{label: operator})
    inputs = Locator.locator(rule, ~s|input[type="number"]|)
    Expect.to_have_count!(inputs, length(values))

    values
    |> Enum.with_index()
    |> Enum.each(fn {value, index} ->
      Locator.fill!(Locator.nth(inputs, index), value)
      Locator.blur!(Locator.nth(inputs, index))
    end)

    textarea = Locator.locator(rule, "textarea")
    Locator.fill!(textarea, feedback)
    Locator.blur!(textarea)
    wait_for_saves(po)
  end

  # ------------------------------------------------------------ editing commands

  def copy_selected_part(po) do
    po |> selection_toolbar_button("Copy") |> Locator.click!()
    Expect.to_be_visible!(paste_button(po))
  end

  @doc "The paste button only exists while a part is on the clipboard."
  def paste_button(po) do
    po |> component_toolbar() |> Locator.get_by_role(:button, name: "Paste Component", exact: true)
  end

  def paste_with_toolbar(po) do
    Expect.to_be_enabled!(paste_button(po))
    Locator.click!(paste_button(po))
    wait_for_saves(po)
  end

  @doc "Ctrl/Cmd+V only pastes while a stage part has focus."
  def paste_with_keyboard(po, focus_part_id) do
    po |> part(focus_part_id) |> Locator.click!()
    Keyboard.press!(Page.keyboard(po.page), "ControlOrMeta+v")
  end

  def paste_blocked_modal(po) do
    po.page |> Page.locator(".modal") |> Locator.filter(has_text: "Paste Component")
  end

  def undo_button(po), do: toolbar_column_button(po, ~r/^Undo$/)

  def redo_button(po), do: toolbar_column_button(po, ~r/^Redo$/)

  defp toolbar_column_button(po, label) do
    po
    |> component_toolbar()
    |> Locator.locator(".toolbar-column")
    |> Locator.filter(has: Page.locator(po.page, "label", has_text: label))
    |> Locator.locator("button")
  end

  # ------------------------------------------------------------ scoring overview

  def scoring_overview_button(po) do
    po |> component_toolbar() |> Locator.get_by_role(:button, name: "Scoring Overview", exact: true)
  end

  def scoring_overview(po) do
    po.page |> Page.locator(".modal") |> Locator.filter(has_text: "Scoring Overview")
  end

  def close_scoring_overview(po) do
    po
    |> scoring_overview()
    |> Locator.get_by_role(:button, name: "Close")
    |> Locator.first()
    |> Locator.click!()

    Expect.to_be_hidden!(scoring_overview(po))
  end

  # ------------------------------------------------------------ flowchart

  def flowchart_node(po, title) do
    po
    |> flowchart_nodes()
    |> Locator.filter(has: Page.locator(po.page, ".title-text", has_text: ~r/^#{escape_reg_exp(title)}$/))
  end

  def select_flowchart_screen(po, title) do
    po
    |> flowchart_node(title)
    |> Locator.locator(".node-box")
    |> Locator.click!(position: %{x: 8, y: 8})

    po
    |> flowchart_sidebar()
    |> Locator.locator(".screen-title")
    |> Expect.to_contain_text!(title, timeout: 10_000)
  end

  def validation_errors(po) do
    po |> flowchart_sidebar() |> Locator.locator(".validation-error h3")
  end

  defp paths(po) do
    po |> flowchart_sidebar() |> Locator.locator(".path-editor-completed, .path-editor-incomplete")
  end

  # Opens the path at `index` and sets its type and destination.
  defp edit_path(po, index, type, destination) do
    path = po |> paths() |> Locator.nth(index)
    Expect.to_be_visible!(path, timeout: 10_000)
    unless editing?(po, path), do: Locator.click!(path)
    complete_path(po, path, type, destination)
  end

  # Adds a rule; the editor opens the new path in edit mode, wherever it sorts.
  defp add_path(po, type, destination) do
    count = po |> paths() |> Locator.count!()
    po |> flowchart_sidebar() |> Locator.get_by_role(:button, name: "Add Rule") |> Locator.click!()
    Expect.to_have_count!(paths(po), count + 1)

    new_path =
      po
      |> paths()
      |> Locator.filter(has: Page.get_by_role(po.page, :button, name: "Done", exact: true))

    Expect.to_have_count!(new_path, 1)
    complete_path(po, new_path, type, destination)
  end

  # Sets an open path's type and destination. Screens with a single available
  # path type render a label instead of a type select.
  defp complete_path(po, path, type, destination) do
    done = done_button(path)
    Expect.to_be_visible!(done)

    type_select = Locator.locator(path, ":scope > select")

    if Locator.count!(type_select) > 0 do
      Locator.select_option!(type_select, %{label: type})
    else
      path |> Locator.locator(":scope > label") |> Locator.first() |> Expect.to_have_text!(type)
    end

    if destination do
      path
      |> Locator.locator(".destination-section select")
      |> Locator.select_option!(%{label: destination})
    end

    Locator.click!(done)

    po
    |> flowchart_sidebar()
    |> Locator.get_by_role(:button, name: "Done")
    |> Expect.to_have_count!(0)

    wait_for_saves(po)
  end

  defp done_button(scope), do: Locator.get_by_role(scope, :button, name: "Done", exact: true)

  defp editing?(_po, path) do
    case path |> done_button() |> Locator.is_visible() do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp delete_path(po, index) do
    count = po |> paths() |> Locator.count!()
    path = po |> paths() |> Locator.nth(index)
    unless editing?(po, path), do: Locator.click!(path)
    path |> Locator.get_by_role(:button, name: "Delete", exact: true) |> Locator.click!()
    confirm = Page.locator(po.page, "#btnDelete", has_text: "Delete Rule")
    Locator.click!(confirm)
    Expect.to_be_hidden!(confirm)
    Expect.to_have_count!(paths(po), count - 1)
    wait_for_saves(po)
  end

  @doc """
  Makes a flowchart screen's outgoing paths match `rules` (a list of `{type, destination}`,
  destination `nil` for types that do not navigate). Adding screens from
  the Screen Panel also adds "Unknown Rule" paths, the editor re-sorts paths
  by priority after each edit, and a screen never drops to zero paths, so
  extra paths are deleted first and each rule then claims a path that does
  not match an already configured rule.
  """
  def set_paths(po, screen_title, rules) do
    rules = Enum.map(rules, &normalize_rule/1)
    select_flowchart_screen(po, screen_title)
    delete_extra_paths(po, length(rules))

    Enum.reduce(rules, [], fn {type, destination} = rule, configured ->
      case first_unconfigured_path_index(po, configured) do
        -1 -> add_path(po, type, destination)
        index -> edit_path(po, index, type, destination)
      end

      configured ++ [rule]
    end)

    Expect.to_have_count!(paths(po), length(rules))

    for {type, destination} <- rules do
      po
      |> matching_paths(type, destination)
      |> Expect.message(
        "#{screen_title} should have a \"#{type}\" path#{if destination, do: " to #{destination}", else: ""}"
      )
      |> Expect.to_have_count!(1)
    end

    wait_for_saves(po)
  end

  defp normalize_rule({type}), do: {type, nil}
  defp normalize_rule({type, destination}), do: {type, destination}

  defp delete_extra_paths(po, size) do
    count = po |> paths() |> Locator.count!()

    if count > size do
      delete_path(po, count - 1)
      delete_extra_paths(po, size)
    end
  end

  defp matching_paths(po, type, destination) do
    # Case-sensitive patterns, so "Correct" does not match "Any Incorrect".
    po
    |> paths()
    |> Locator.filter(has_text: ~r/#{escape_reg_exp(type)}/)
    |> Locator.filter(has_text: ~r/#{escape_reg_exp(destination || type)}/)
  end

  defp first_unconfigured_path_index(po, configured) do
    texts = po |> paths() |> Locator.all_inner_texts!()

    Enum.find_index(texts, fn text ->
      not Enum.any?(configured, fn {type, destination} ->
        String.contains?(text, type) and String.contains?(text, destination || type)
      end)
    end) || -1
  end

  defp escape_reg_exp(value) do
    Regex.replace(~r/[.*+?^${}()|[\]\\]/, value, "\\\\\\0")
  end
end
