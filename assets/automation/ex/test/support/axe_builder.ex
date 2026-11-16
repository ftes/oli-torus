defmodule OliE2E.AxeBuilder do
  @moduledoc """
  A port of `@axe-core/playwright`'s `AxeBuilder` (`include/2` and
  `analyze!/1`, non-legacy mode). It runs the axe-core that
  `assets/node_modules` resolves for `@axe-core/playwright`.
  """

  alias Playwright.ElementHandle
  alias Playwright.Frame
  alias Playwright.JSHandle
  alias Playwright.Page

  defstruct [:page, includes: [], excludes: [], option: %{}]

  def new(page), do: %__MODULE__{page: page}

  def include(builder, selector),
    do: %{builder | includes: builder.includes ++ [selector]}

  def exclude(builder, selector),
    do: %{builder | excludes: builder.excludes ++ [selector]}

  def with_tags(builder, tags),
    do: %{builder | option: Map.put(builder.option, :runOnly, %{type: "tag", values: List.wrap(tags)})}

  def with_rules(builder, rules),
    do: %{builder | option: Map.put(builder.option, :runOnly, %{type: "rule", values: List.wrap(rules)})}

  def analyze!(%__MODULE__{page: page} = builder) do
    context = normalize_context(builder.includes, builder.excludes)
    Page.evaluate!(page, script())

    if !Page.evaluate!(page, ~s|typeof window.axe.runPartial === "function"|) do
      raise "legacy mode is not ported"
    end

    partials =
      run_partial_recursive(builder, Page.main_frame(page), context, true)

    finish_run(builder, partials)
  end

  defp normalize_context(includes, excludes) do
    base = %{exclude: excludes, include: []}
    if includes != [], do: %{base | include: includes}, else: base
  end

  defp run_partial_recursive(builder, frame, context, initiator) do
    frame_contexts =
      Frame.evaluate!(
        frame,
        "({ context }) => window.axe.utils.getFrameContexts(context)",
        %{context: context}
      )

    partial =
      Playwright.Promise.async(fn ->
        Frame.evaluate!(
          frame,
          "({ context, options }) => window.axe.runPartial(context, options)",
          %{context: context, options: builder.option}
        )
      end)

    children =
      for %{"frameSelector" => frame_selector, "frameContext" => frame_context} <-
            frame_contexts do
        try do
          iframe_handle =
            Frame.evaluate_handle!(
              frame,
              "({ frameSelector }) => window.axe.utils.shadowSelect(frameSelector)",
              %{frameSelector: frame_selector}
            )

          child_frame =
            iframe_handle
            |> JSHandle.as_element()
            |> ElementHandle.content_frame!()

          if child_frame do
            inject(builder, child_frame)
            run_partial_recursive(builder, child_frame, frame_context, false)
          end
        rescue
          _ -> nil
        end
      end

    case Playwright.Promise.await(partial) do
      {:ok, parent} ->
        [parent | Enum.flat_map(children, &(&1 || [nil]))]

      {:error, error} ->
        if initiator, do: raise(error), else: [nil]
    end
  end

  # Upstream races the injection against a 1 s timeout.
  defp inject(builder, frame) do
    Frame.evaluate!(frame, script())
    Frame.evaluate!(frame, axe_configure(builder))
  end

  defp finish_run(%__MODULE__{page: page, option: options} = builder, partials) do
    blank_page = page |> Page.context() |> Playwright.BrowserContext.new_page!()
    Page.evaluate!(blank_page, script())
    Page.evaluate!(blank_page, axe_configure(builder))

    Page.evaluate!(
      blank_page,
      "(partials) => { window.partialResults = JSON.stringify(partials); }",
      partials
    )

    Page.evaluate!(
      blank_page,
      "({ options }) => window.axe.finishRun(JSON.parse(window.partialResults), options)",
      %{options: options}
    )
  end

  defp axe_configure(%__MODULE__{page: page}) do
    has_run_partial =
      Page.evaluate!(page, ~s|typeof window.axe?.runPartial === "function"|)

    allowed =
      if has_run_partial,
        do: ~s|allowedOrigins: ["<same_origin>"],|,
        else: ~s|allowedOrigins: ["<unsafe_all_origins>"],|

    """
    ;axe.configure({
      #{allowed}
      branding: { application: 'playwright' }
    })
    """
  end

  defp script do
    :persistent_term.get({__MODULE__, :source}, nil) ||
      (
        source = File.read!(axe_core_path())
        :persistent_term.put({__MODULE__, :source}, source)
        source
      )
  end

  # axe-core next to `@axe-core/playwright` (installed by `npm ci` in assets/automation).
  defp axe_core_path do
    automation = Path.expand("../../..", __DIR__)

    {path, 0} =
      System.cmd(
        "node",
        [
          "-p",
          "require.resolve('axe-core', { paths: [require.resolve('@axe-core/playwright')] })"
        ],
        cd: automation
      )

    String.trim(path)
  end
end
