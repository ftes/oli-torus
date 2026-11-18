defmodule OliE2E.Pom.AdvancedAuthor do
  @moduledoc """
  Port of src/systems/torus/pom/page/AdvancedAuthorPO.ts (only the methods the
  advanced-author spec and AdvancedAuthorTask use).

  Page object for the adaptive Advanced Author editor.

  Advanced Author shares its stage, save pipeline, and property-panel
  field-id convention with Simple Author — both run the same underlying
  authoring app (`apps/authoring`) — but its component
  toolbar is a different React component (`ExpertHeaderNav` /
  `AddComponentToolbar`, vs. Simple Author's `FlowchartHeaderNav`) and its
  screen tree is `SequenceEditor`, not Simple Author's flat `ScreenList`.
  There is no Flowchart/Screen Panel toggle here: the editor loads directly
  onto the canvas.

  Property-panel inputs carry generated ids such as
  `component_part_<rand>_<partId>_custom_<field>` for a selected part, or
  `<formId>_<field>` for the Screen/Lesson tabs; the stable part is the field
  suffix, so fields are located by `[id$="_<suffix>"]` inside the active tab
  (confirmed identical to Simple Author's convention).

  The JS class keeps `pendingSaves`/`lastSaveActivity` in fields mutated from
  `page.on(...)` listeners; here they live in an Agent (`saves`).
  """

  import ExUnit.Assertions

  alias OliE2E.Pom.BasicPracticePage
  alias Playwright.{Expect, Keyboard, Locator, Page, Request}

  defstruct [:page, :saves, :stage, :toolbar, :sequence_editor, :left_panel, :right_panel, :page_po]

  # Part slugs for the components this suite drives; each renders on stage as a
  # custom element named after the slug with `-` for `_` (confirmed against
  # `assets/src/components/parts/*/manifest.json`'s `delivery.element`).
  #   :janus_text_flow | :janus_image | :janus_video | :janus_mcq |
  #   :janus_multi_line_text | :janus_input_number | :janus_item_bank
  # Tabs: "Lesson" | "Screen" | "Component"
  # Media pickers: "Select Image" | "Select Video File"
  # Part widths: "100%" | "50% left" | "50% right"
  # Rule names: "Initial State" | "correct" | "defaultWrong"

  @save_request ~r{/api/v1/(storage/project/[^/]+/resource|project/[^/]+/(resource|activity))}
  # Longer than the editor's 500ms save debounce, so a pending write always shows up.
  @save_quiet_ms 800

  # The "frequently used" toolbar row (`ExpertHeaderNav` / `AddComponentToolbar`)
  # renders each button as a bare `<button><img src="icon-part-<x>.svg"></button>`
  # with no accessible name at all (no `alt`, `title`, or `aria-label`), so these
  # components can only be added by matching the icon's `src`.
  @toolbar_icon %{
    janus_text_flow: "icon-part-text.svg",
    janus_image: "icon-part-image.svg",
    janus_video: "icon-part-video.svg",
    janus_mcq: "icon-part-mcq.svg"
  }

  # Components outside the frequently-used row are added through the "More
  # Components" popover instead, whose entries DO carry a visible label, so
  # they're matched by accessible name rather than icon `src`.
  @more_components_label %{
    janus_multi_line_text: "MultiLine Text Input",
    janus_input_number: "Number Input",
    janus_item_bank: "Item Bank"
  }

  def new(page) do
    {:ok, saves} = Agent.start(fn -> %{pending: MapSet.new(), last_activity: 0} end)

    po = %__MODULE__{
      page: page,
      saves: saves,
      page_po: BasicPracticePage.new(page),
      stage: Page.locator(page, "section.aa-stage"),
      toolbar: Page.locator(page, "#advanced-authoring nav.aa-header-nav"),
      sequence_editor: Page.locator(page, ".aa-sequence-editor"),
      left_panel: Page.locator(page, ".aa-panel.left-panel"),
      right_panel: Page.locator(page, ".aa-panel.right-panel")
    }

    Page.on(page, :request, fn request ->
      if save_request?(request) do
        Agent.update(saves, fn s ->
          %{s | pending: MapSet.put(s.pending, request), last_activity: now()}
        end)
      end
    end)

    settle = fn request ->
      Agent.update(saves, fn s ->
        if MapSet.member?(s.pending, request),
          do: %{s | pending: MapSet.delete(s.pending, request), last_activity: now()},
          else: s
      end)
    end

    Page.on(page, :request_finished, settle)
    Page.on(page, :request_failed, settle)

    po
  end

  # ------------------------------------------------------------ persistence

  # Waits until no Advanced Author write is in flight and none started for a
  # quiet window. The window is measured from the call too, so a write still
  # inside the editor's 500ms save debounce is not missed.
  def wait_for_saves(po, timeout \\ 30_000) do
    called_at = now()
    deadline = called_at + timeout
    do_wait_for_saves(po, called_at, deadline, timeout)
  end

  defp do_wait_for_saves(%{saves: saves, page: page} = po, called_at, deadline, timeout) do
    if now() < deadline do
      %{pending: pending, last_activity: last} = Agent.get(saves, & &1)
      quiet_for = now() - max(last, called_at)

      if MapSet.size(pending) == 0 and quiet_for >= @save_quiet_ms do
        :ok
      else
        Page.wait_for_timeout!(page, 250)
        do_wait_for_saves(po, called_at, deadline, timeout)
      end
    else
      %{pending: pending} = Agent.get(saves, & &1)

      raise "Advanced Author saves did not settle within #{timeout}ms (#{MapSet.size(pending)} pending)"
    end
  end

  # Reloads the editor after pending writes settle.
  def reload_editor(%{page: page} = po) do
    wait_for_saves(po)
    Page.reload!(page)
    wait_for_editor_loaded(po)
  end

  # Waits for the editor and leaves it editable: a reopened lesson can start
  # in read-only mode.
  def wait_for_editor_loaded(%{page: page} = po) do
    po.toolbar
    |> Expect.message("Advanced Author toolbar should load")
    |> Expect.to_be_visible!(timeout: 60_000)

    BasicPracticePage.disable_adaptive_read_only(po.page_po)
    Expect.to_be_visible!(po.stage, timeout: 30_000)

    Page.wait_for_function!(page, "() => customElements.get('janus-mcq') != null", nil, timeout: 30_000)
  end

  # ------------------------------------------------------------ screens

  # Adds a top-level screen from the Sequence Editor's "+" menu and renames
  # it. Unlike Simple Author, there is no creation modal: the item is created
  # and selected immediately, and its title is set afterward through the
  # Screen tab's "Title" field.
  def add_screen(po, title), do: add_sequence_item(po, "Screen", title)

  # Adds a top-level Layer the same way `add_screen` adds a Screen — same "+"
  # menu, same create-then-rename lifecycle (`SequenceEditor.tsx`'s
  # `handleItemAdd` is shared by all three "+" menu entries, differing only
  # by an `isLayer`/`isBank` flag). A Layer renders its own parts stacked
  # together with whichever of its subscreens (added via `add_subscreen`) is
  # currently active, rather than being a plain top-level screen.
  def add_layer(po, title), do: add_sequence_item(po, "Layer", title)

  defp add_sequence_item(%{page: page} = po, kind, title) do
    ensure_left_panel_open(po)
    before = sequence_item_titles(po)

    page |> Page.locator("#sequence-add") |> Locator.click!()
    po |> sequence_add_menu_item(kind) |> Locator.click!()

    rename_new_sequence_item(po, before, title)
  end

  # Adds a subscreen nested under an existing top-level Layer/Question Bank
  # row, via that row's "⋮" context-menu "Add Subscreen" entry, then renames
  # it the same way `add_screen` does. This is the only way to reach the
  # "responsive subscreens" scope Raphael described: verifying a part's
  # `responsiveLayoutWidth` behavior still works when the part lives on a
  # subscreen instead of a top-level screen.
  def add_subscreen(po, parent_title, title) do
    select_screen(po, parent_title)
    before = sequence_item_titles(po)

    po |> sequence_item(parent_title) |> Locator.locator(".aa-context-menu-trigger") |> Locator.click!()
    po |> context_menu_item("Add Subscreen") |> Locator.click!()

    rename_new_sequence_item(po, before, title)
  end

  # Selects whichever sequence item appeared since `before` was captured and
  # renames it through the Screen tab's "Title" field. Shared by every way of
  # creating a sequence item (top-level "+" menu, or a row's "Add Subscreen"
  # context-menu entry) — they differ only in how the new item is triggered.
  defp rename_new_sequence_item(po, before, title) do
    new_title = wait_for_new_sequence_item_title(po, before)
    select_screen(po, new_title)
    # The new item's own creation write must land before the rename, or the
    # two concurrent writes can persist the template title over the rename.
    wait_for_saves(po)
    open_tab(po, "Screen")
    fill_field(po, "title", title)
    wait_for_saves(po)
  end

  # An item in the "+" menu ("Screen", "Layer", "Question Bank"). These are
  # Bootstrap `Dropdown.Item`s with an icon rendered via a Font Awesome `<i>`
  # tag; the icon's CSS-generated glyph leaks into the computed accessible
  # name, so `getByRole('button', { name: ... })` never matches even though
  # the element has an explicit `role="button"`. Matching by DOM text content
  # (`hasText`) sidesteps that: `hasText` compares `textContent`, which the
  # icon's `::before` glyph does not affect.
  defp sequence_add_menu_item(%{page: page}, label) do
    page |> Page.locator(".dropdown-menu.show a.dropdown-item") |> Locator.filter(has_text: label)
  end

  # A sequence row's own "⋮" context menu ("Add Subscreen", "Rename", ...).
  # Unlike the "+" menu's dropdown, this one is rendered globally (a single
  # popup reused for whichever row triggered it, `LeftMenu`/
  # `SequenceItemContextMenu.tsx`) and its wrapper never actually receives
  # the `.dropdown-menu.show` class its own JSX names (the `show` prop that
  # class expression reads is never passed down) — only its items' visible
  # text can be relied on.
  defp context_menu_item(%{page: page}, label) do
    page |> Page.locator(".dropdown-item") |> Locator.filter(has_text: label)
  end

  def select_screen(po, title) do
    ensure_left_panel_open(po)
    po |> sequence_item(title) |> Locator.click!()
    expect_active_screen(po, title)
  end

  # A newly added part always starts at (or near) x:0, y:0 on its screen (the
  # canvas's `newPartAddOffset` resets for every screen), which sits directly
  # under the left Sequence Editor panel: the panel then intercepts clicks on
  # the part's floating `.active-selection-toolbar`. Collapsing the panel
  # before any such interaction avoids this; `add_screen`/`select_screen`
  # reopen it since sequence navigation needs it.
  defp ensure_left_panel_open(po) do
    unless left_panel_open?(po) do
      po |> left_panel_toggle() |> Locator.click!()
      Expect.to_have_class!(po.left_panel, ~r/open/, timeout: 10_000)
    end
  end

  defp collapse_left_panel(po) do
    if left_panel_open?(po) do
      po |> left_panel_toggle() |> Locator.click!()
      Expect.not_to_have_class!(po.left_panel, ~r/open/, timeout: 10_000)
    end
  end

  defp left_panel_open?(po), do: Locator.evaluate!(po.left_panel, "el => el.classList.contains('open')")

  defp left_panel_toggle(%{page: page}), do: Page.locator(page, "button.aa-panel-side-toggle.left")

  defp expect_active_screen(po, title) do
    po |> sequence_item(title) |> Expect.to_have_class!(~r/active/, timeout: 30_000)
  end

  defp sequence_item(%{page: page} = po, title) do
    po.sequence_editor
    |> Locator.locator(".aa-sequence-item")
    |> Locator.filter(has: Page.locator(page, ".title", has_text: ~r/^#{Regex.escape(title)}$/))
  end

  defp sequence_item_titles(po) do
    po.sequence_editor |> Locator.locator(".aa-sequence-item .title") |> Locator.all_text_contents!()
  end

  # Waits for a sequence item whose title was not in `before` and returns it.
  defp wait_for_new_sequence_item_title(po, before) do
    Expect.poll!(fn -> length(sequence_item_titles(po)) end, &assert(&1 > length(before)), timeout: 30_000)

    after_titles = sequence_item_titles(po)
    added = Enum.find(after_titles, fn title -> title not in before end)
    if !added, do: raise("A new sequence item should have been added")
    added
  end

  # ------------------------------------------------------------ stage parts

  def part(po, part_id), do: Locator.locator(po.stage, ~s|[id="#{part_id}"]|)

  def parts_of_type(po, type), do: Locator.locator(po.stage, type)

  def part_ids(po, type) do
    po |> parts_of_type(type) |> Locator.evaluate_all!("elements => elements.map((e) => e.id)")
  end

  def select_part(po, part_id) do
    part = part(po, part_id)
    Expect.to_be_visible!(part, timeout: 30_000)
    Locator.click!(part)
    Expect.to_have_attribute!(tab(po, "Component"), "aria-selected", "true", timeout: 10_000)
    # Parts commonly sit at x:0, y:0 (see `ensure_left_panel_open`'s comment),
    # which puts their floating toolbar under the left panel.
    collapse_left_panel(po)
  end

  # Clicks whichever toolbar control adds `component` (the frequently-used
  # row by icon, or "More Components" by label) and returns the id of the
  # part it added.
  def add_component(po, component) do
    element_type = component |> Atom.to_string() |> String.replace("_", "-")
    before = part_ids(po, element_type)

    case Map.get(@toolbar_icon, component) do
      nil ->
        label = Map.get(@more_components_label, component)
        if !label, do: raise("No toolbar mapping is defined for #{component}")
        add_from_more_components(po, label)

      icon ->
        click_toolbar_icon(po, icon)
    end

    po |> parts_of_type(element_type) |> Expect.to_have_count!(length(before) + 1, timeout: 10_000)
    after_ids = part_ids(po, element_type)
    added = Enum.find(after_ids, fn id -> id not in before end)
    if !added, do: raise("A new #{element_type} part should be added")
    wait_for_saves(po)
    added
  end

  defp click_toolbar_icon(po, icon) do
    button = toolbar_icon_button(po, icon)
    Expect.to_be_enabled!(button, timeout: 30_000)
    Locator.click!(button)
  end

  defp toolbar_icon_button(po, icon) do
    po.toolbar |> Locator.locator(~s|img[src="/images/icons/#{icon}"]|) |> Locator.locator("xpath=..")
  end

  # Each popover entry's icon carries a `title` attribute (its description),
  # which — like the "+" menu's Font Awesome icons (see `sequence_add_menu_item`)
  # — leaks into the computed accessible name, so `getByRole(..., { name })`
  # does not match. Matching by DOM text content (`hasText`) sidesteps it.
  defp add_from_more_components(%{page: page} = po, label) do
    click_toolbar_icon(po, "icon-componentList.svg")
    popover = Page.locator(page, "#moreComponents-popover")
    Expect.to_be_visible!(popover, timeout: 10_000)
    popover |> Locator.locator(".list-group-item") |> Locator.filter(has_text: label) |> Locator.click!()
  end

  # Opens the config modal for a text-flow part and replaces its text. The
  # modal (`ConfigurationModal` in `apps/authoring/components/EditingCanvas`)
  # is shared with Simple Author. The trigger is the same
  # `.active-selection-toolbar button[title="Edit"]` Simple Author uses too
  # (rendered by the shared `LayoutEditor`, under
  # `components/activities/adaptive`) — a *different*, unlabeled "Edit JSON"
  # affordance also exists in the Component tab's own toolbar
  # (`PartPropertyEditor`), which is not this one.
  def set_text_flow_text(%{page: page} = po, part_id, text) do
    select_part(po, part_id)
    po |> selection_toolbar_button("Edit") |> Locator.click!()

    modal = Page.locator(page, ".config-modal")
    editor = Locator.locator(modal, ".ql-editor")
    Expect.to_be_visible!(editor, timeout: 15_000)
    Locator.click!(editor)
    page |> Page.keyboard() |> Keyboard.press!("ControlOrMeta+A")
    page |> Page.keyboard() |> Keyboard.type!(text)
    Expect.to_have_text!(editor, text)
    modal |> Locator.get_by_role(:button, name: "Save") |> Locator.click!()
    Expect.to_be_hidden!(modal, timeout: 15_000)
    po |> part(part_id) |> Expect.to_contain_text!(text, timeout: 15_000)
    wait_for_saves(po)
  end

  # The selected part's floating copy/edit/delete toolbar.
  defp selection_toolbar_button(%{page: page}, title) do
    page |> Page.locator(~s|.active-selection-toolbar button[title="#{title}"]|) |> Locator.first()
  end

  # Chooses a media source through the picker's "External URL" tab. The
  # picker (`MediaPickerModal` / `UrlOrUpload`, under
  # `apps/authoring/components`) is shared with Simple Author and was built
  # for Advanced Author first, so the flow is identical.
  def set_media_url(%{page: page} = po, picker_label, url) do
    po |> tab_panel() |> Locator.get_by_role(:button, name: picker_label) |> Locator.click!()

    modal = page |> Page.locator(".modal") |> Locator.filter(has_text: picker_label) |> Locator.last()
    Expect.to_be_visible!(modal)
    modal |> Locator.get_by_role(:button, name: "External URL") |> Locator.click!()
    input = Locator.get_by_placeholder(modal, "Enter the media URL address")
    Locator.fill!(input, url)
    modal |> Locator.get_by_role(:button, name: "OK", exact: true) |> Locator.click!()
    Expect.to_be_hidden!(modal)
    po |> tab_panel() |> Expect.to_contain_text!(url)
    wait_for_saves(po)
  end

  # Sets a part's responsive width. Only visible once the lesson's "Enable
  # Responsive Layout" setting (Lesson tab) is on; a part added before that
  # can render with this select disabled. The resulting `.responsive-item`
  # wrapper and its `half-width`/`full-width`/`responsive-align-*` classes
  # come from the same shared `LayoutEditor` Simple Author uses.
  def set_part_width(po, part_id, width) do
    select_part(po, part_id)
    select = field(po, "Size_responsiveLayoutWidth")
    Expect.to_be_visible!(select)
    Locator.select_option!(select, %{label: width})

    po
    |> responsive_item(part_id)
    |> Expect.to_have_class!(if(width == "100%", do: ~r/full-width/, else: ~r/half-width/), timeout: 10_000)

    wait_for_saves(po)
  end

  def responsive_item(po, part_id) do
    Locator.locator(po.stage, ~s|.responsive-item[data-part-id="#{part_id}"]|)
  end

  # ------------------------------------------------------------ adaptivity rules

  # Selects a rule in the selected part's Adaptivity list (bottom panel).
  # Every part starts with "Initial State", "correct", and "defaultWrong".
  def select_rule(po, name) do
    # The Adaptivity list lives in the same left panel as the Sequence
    # Editor, which `select_part` collapses to dodge the active-selection
    # toolbar overlap (see `ensure_left_panel_open`'s comment) — reopen it.
    ensure_left_panel_open(po)
    po |> rule_list_item(name) |> Locator.click!()
  end

  defp rule_list_item(%{page: page}, name) do
    page
    |> Page.locator(".aa-rules-list-item")
    |> Locator.filter(has: Page.locator(page, ".title", has_text: ~r/^#{Regex.escape(name)}$/))
  end

  # Sets the currently selected rule's single condition (adding one first if
  # needed). The target/value inputs are plain text fields — no Variable
  # Picker dialog is required, unlike the manual authoring flow the
  # regression spreadsheet describes. Only one condition per rule is
  # supported here; the default "=" operator is left as is.
  def set_rule_condition(%{page: page} = po, target, value) do
    target_input = page |> Page.locator(~s|input[placeholder="Target"]|) |> Locator.first()

    if Locator.count!(target_input) == 0 do
      page |> Page.locator(".aa-conditions .dropdown-toggle.aa-add-button") |> Locator.click!()

      page
      |> Page.locator(".dropdown-menu.show")
      |> Locator.locator("a, button")
      |> Locator.filter(has_text: "Single Condition")
      |> Locator.first()
      |> Locator.click!()
    end

    Locator.fill!(target_input, target)
    Locator.press!(target_input, "Tab")
    wait_for_saves(po)

    value_input = page |> Page.locator(~s|input[placeholder="Value"]|) |> Locator.first()
    Locator.fill!(value_input, value)
    Locator.press!(value_input, "Tab")
    wait_for_saves(po)
  end

  # Sets the currently selected rule's "Navigate To" action (adding one first
  # if needed) to the given screen. The destination control
  # (`ScreenDropdownTemplate`) is a Bootstrap dropdown, not a `<select>`, and
  # its toggle's id is regenerated on every change, so it's located by its
  # "Navigate To" label instead.
  def set_rule_destination(%{page: page} = po, screen_title) do
    nav_toggle = navigate_to_toggle(po)

    nav_toggle =
      if Locator.count!(nav_toggle) == 0 do
        page |> Page.locator("#adaptive-editor-add-context-trigger") |> Locator.click!()

        page
        |> Page.locator(".dropdown-menu.show a.dropdown-item")
        |> Locator.filter(has_text: "Navigate To")
        |> Locator.click!()

        navigate_to_toggle(po)
      else
        nav_toggle
      end

    Locator.click!(nav_toggle)

    page
    |> Page.locator(".dropdown-menu.show .aa-sequence-item")
    |> Locator.filter(has_text: ~r/^#{Regex.escape(screen_title)}$/)
    |> Locator.click!()

    wait_for_saves(po)
    po |> navigate_to_toggle() |> Expect.to_have_text!(screen_title)
  end

  defp navigate_to_toggle(%{page: page}) do
    page
    |> Page.locator(".aa-action")
    |> Locator.filter(has_text: "Navigate To")
    |> Locator.locator(".dropdown-toggle")
  end

  # ------------------------------------------------------------ editing commands

  # Copies the selected part. `.active-selection-toolbar button[title="Copy"]`
  # dispatches the shared `setCopiedPart` Redux action (`EditingCanvas`'s
  # `handlePartCopy`, under `apps/authoring/components/EditingCanvas`) — the
  # same action Simple Author's copy relies on — which is why a paste
  # affordance then appears in `AddComponentToolbar` here too.
  def copy_selected_part(po) do
    po |> selection_toolbar_button("Copy") |> Locator.click!()
    po |> paste_button() |> Expect.to_be_visible!()
  end

  # Only exists on the toolbar while a part is on the clipboard.
  def paste_button(po), do: toolbar_icon_button(po, "icon-paste.svg")

  def paste_with_toolbar(po) do
    po |> paste_button() |> Expect.to_be_enabled!()
    po |> paste_button() |> Locator.click!()
    wait_for_saves(po)
  end

  # Ctrl/Cmd+V only pastes while a stage part has focus.
  def paste_with_keyboard(%{page: page} = po, focus_part_id) do
    po |> part(focus_part_id) |> Locator.click!()
    page |> Page.keyboard() |> Keyboard.press!("ControlOrMeta+v")
  end

  def undo_button(po), do: toolbar_icon_button(po, "icon-undo.svg")

  def redo_button(po), do: toolbar_icon_button(po, "icon-redo.svg")

  # ------------------------------------------------------------ property panel

  defp tab(po, name), do: Locator.get_by_role(po.right_panel, :tab, name: name, exact: true)

  def open_tab(po, name) do
    po |> tab(name) |> Locator.click!()
    po |> tab(name) |> Expect.to_have_attribute!("aria-selected", "true")
  end

  # The content of the active right-panel tab.
  def tab_panel(po), do: Locator.locator(po.right_panel, ".tab-pane.active")

  # Some fields (e.g. ones with a help tooltip, like "Enable Responsive
  # Layout") render the same id on their wrapper `<div>`s AND the actual
  # `<input>`/`<select>` — a real app bug (logged to the console as
  # "Multiple IDs detected") — so this only matches real form-control tags,
  # never a wrapper div sharing the id.
  def field(po, suffix) do
    po
    |> tab_panel()
    |> Locator.locator(~s|input[id$="_#{suffix}"], select[id$="_#{suffix}"], textarea[id$="_#{suffix}"]|)
    |> Locator.first()
  end

  # Fills a property field, blurs it, and waits for the write: quick
  # successive edits can otherwise persist an older form state over a newer
  # one (same debounce behavior as Simple Author).
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

  defp save_request?(request) do
    Request.method(request) in ["PUT", "POST"] and Regex.match?(@save_request, Request.url(request))
  end

  defp now, do: System.monotonic_time(:millisecond)
end
