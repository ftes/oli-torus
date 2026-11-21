defmodule OliE2E.Pom.AdaptiveDeck do
  @moduledoc """
  Port of src/systems/torus/pom/delivery/AdaptiveDeckPO.ts: page object for the adaptive
  lesson "deck" player. Only the methods the @pr specs use are ported (the strict-walk,
  widget and scan helpers are not).

  `lastEvaluation`, a mutable field of the JS class, lives in an `Agent` started by `new/1`
  (linked to the calling process).
  """

  alias Playwright.{Locator, Page}

  defstruct [:page, :last_evaluation]

  @footer_button ".checkBtn:not([disabled]), .closeFeedbackBtn:not([disabled])"
  @busy_footer_button ".buttonContainer .checkBtn[disabled], .buttonContainer .closeFeedbackBtn[disabled]"
  @canvas_nav_button ~s|button[data-janus-type="janus-navigation-button"]:not([disabled])|
  @evaluation_wait 30_000
  @action_timeout [timeout: 8_000]

  def new(page) do
    {:ok, agent} = Agent.start_link(fn -> nil end)
    %__MODULE__{page: page, last_evaluation: agent}
  end

  # ------------------------------------------------------------ lifecycle

  @doc """
  The footer control stays disabled until the deck finishes initialising the
  screen's parts (isLoading || !initPhaseComplete), so an ENABLED control is
  the readiness signal.
  """
  def wait_for_deck_ready(%{page: page}) do
    page
    |> Page.locator("[data-janus-type], .checkBtn, .closeFeedbackBtn")
    |> Locator.first()
    |> Locator.wait_for!(state: :attached, timeout: 30_000)

    # screens driven only by in-canvas controls have no footer
    page
    |> Page.locator(@footer_button)
    |> Locator.first()
    |> Locator.wait_for(state: :visible, timeout: 30_000)

    :ok
  end

  @doc "finalizeLesson redirects out of the deck or retires the footer."
  def lesson_ended?(%{page: page}) do
    if not String.contains?(Page.url(page), "/adaptive_lesson/") do
      true
    else
      case Page.evaluate(page, """
           () => {
             const container = document.querySelector('.buttonContainer');
             return !!container && container.classList.contains('displayNone');
           }
           """) do
        {:ok, ended} -> ended == true
        _ -> false
      end
    end
  end

  @doc """
  Whether the feedback popup is open. The deck swaps the footer button's
  class to closeFeedbackBtn exactly while feedback shows, so the control's
  presence is the signal.
  """
  def feedback_visible(%{page: page}) do
    case page |> Page.locator(".closeFeedbackBtn") |> Locator.first() |> Locator.is_visible() do
      {:ok, visible} -> visible
      _ -> false
    end
  end

  def feedback_text(%{page: page}) do
    case page
         |> Page.locator(~s|.feedbackContainer, [class*="feedback"]|)
         |> Locator.first()
         |> Locator.inner_text() do
      {:ok, text} -> text
      _ -> ""
    end
  end

  @doc """
  The deck's single footer control, including while it is disabled during a
  check. Its label follows the screen state (the screen's check label, then
  the feedback's button label).
  """
  def footer_button(%{page: page}) do
    page |> Page.locator(".checkContainer .buttonContainer button") |> Locator.first()
  end

  # ------------------------------------------------------------ navigation

  @doc """
  Clicks the screen's primary control (footer button, else canvas navigation
  button) until the screen changes or the lesson ends, at most `max_clicks`
  times; false when it gives up on the same screen. See the JS doc comment.
  """
  def advance(po, max_clicks \\ 6, timeout \\ 12_000) do
    previous = screen_id(po)

    Enum.reduce_while(1..max_clicks//1, nil, fn _i, outcome ->
      give_up_at = now() + @evaluation_wait
      budget = give_up_at + timeout

      case acquire_role(po, previous, timeout, give_up_at, outcome == :evaluating) do
        :changed ->
          {:halt, true}

        nil ->
          {:halt, moved?(po, previous)}

        role ->
          if moved?(po, previous) do
            {:halt, true}
          else
            po.page
            |> Page.locator(if role == :nav, do: @canvas_nav_button, else: @footer_button)
            |> Locator.first()
            |> Locator.click(@action_timeout)

            case wait_for_outcome(po, previous, timeout, budget, role) do
              :changed ->
                {:halt, true}

              :timeout when role == :ack and max_clicks > 1 ->
                raise "advance: acknowledging feedback produced no observable outcome within #{timeout}ms; refusing to click again"

              other ->
                {:cont, other}
            end
          end
      end
    end)
    |> case do
      bool when is_boolean(bool) -> bool
      _ -> false
    end
  end

  # The inner `for (;;)` of advance().
  defp acquire_role(po, previous, timeout, give_up_at, after_evaluating) do
    role = await_control(po, previous, timeout, give_up_at, after_evaluating)

    if role in [:changed, nil] do
      role
    else
      armed = deck_snapshot(po, true)

      cond do
        armed && not armed.busy && role_of(armed) == if(role == :nav, do: nil, else: role) ->
          role

        true ->
          if armed && armed.busy, do: saw_evaluation(po, previous)

          if now() > give_up_at do
            nil
          else
            acquire_role(po, previous, timeout, give_up_at, after_evaluating)
          end
      end
    end
  end

  @doc """
  Strict: click the Check control exactly once. Raises if it is not available.
  """
  def submit_check(%{page: page}) do
    check = page |> Page.locator(".checkBtn:not([disabled])") |> Locator.first()

    unless match?({:ok, true}, Locator.is_visible(check)) do
      raise "strict submit: no enabled .checkBtn on screen"
    end

    Locator.click!(check, @action_timeout)
  end

  @doc "Strict: dismiss the open feedback popup exactly once. Raises if it is not open."
  def acknowledge_feedback(%{page: page}) do
    close = page |> Page.locator(".closeFeedbackBtn:not([disabled])") |> Locator.first()

    unless match?({:ok, true}, Locator.is_visible(close)) do
      raise "strict acknowledge: feedback popup is not open"
    end

    Locator.click!(close, @action_timeout)
  end

  def wait_for_feedback_open(%{page: page}, timeout \\ 15_000) do
    result =
      page
      |> Page.locator(".closeFeedbackBtn")
      |> Locator.first()
      |> Locator.wait_for(state: :visible, timeout: timeout)

    unless result == :ok do
      raise "strict transition: expected feedback popup did not open"
    end

    :ok
  end

  @doc """
  Screen identity, preferring the activity id the deck serialises onto the
  delivery element's `model` attribute; falls back to a text digest (feedback
  text excluded, it renders on the SAME screen after a check).
  """
  def screen_id(%{page: page}) do
    result =
      Page.evaluate(page, """
      () => {
        // [model][context]: janus PARTS also carry a model attribute, so match
        // on context too - only the activity delivery element receives both,
        // otherwise this reads back a part id instead of the screen's activity
        const ids = Array.from(document.querySelectorAll('[model][context]'))
          .map((el) => {
            try {
              return JSON.parse(el.getAttribute('model') || '{}').id ?? null;
            } catch {
              return null;
            }
          })
          .filter((id) => id !== null);
        if (ids.length > 0) return `activity:${ids[ids.length - 1]}`;

        const outsideFeedback = (el) => !el.closest('[class*="feedback"]');
        const heads = Array.from(document.querySelectorAll('h1'))
          .filter(outsideFeedback)
          .map((e) => e.innerText || '')
          .join(' # ');
        const body = Array.from(document.querySelectorAll('[data-janus-type="janus-text-flow"]'))
          .filter(outsideFeedback)
          .map((e) => e.innerText || '')
          .join(' | ');
        return `${heads} :: ${body}`.replace(/\\s+/g, ' ').trim().slice(0, 300);
      }
      """)

    case result do
      {:ok, id} when is_binary(id) -> id
      _ -> ""
    end
  end

  # One in-page read: whether a footer button went disabled since the last
  # arm, whether one is disabled now, and the class of the first footer button
  # match when it is visible. Arming resets that record in the same task, right
  # before a click, and installs the document's observer on first use.
  # nil when the read fails.
  defp deck_snapshot(%{page: page}, arm \\ false) do
    result =
      Page.evaluate(
        page,
        """
        ({ enabled, busy, arm }) => {
          const w = window;
          if (arm) {
            w.__deckEvaluated = false;
            if (!w.__deckRecorder) {
              w.__deckRecorder = new MutationObserver((records) => {
                for (const r of records) {
                  const el = r.target;
                  if (
                    r.attributeName === 'disabled' &&
                    el.closest('.buttonContainer') &&
                    (el.hasAttribute('disabled') || r.oldValue === null)
                  ) {
                    w.__deckEvaluated = true;
                  }
                }
              });
              w.__deckRecorder.observe(document.documentElement, {
                subtree: true,
                attributes: true,
                attributeFilter: ['disabled'],
                attributeOldValue: true,
              });
            }
          }
          const button = document.querySelector(enabled);
          const box = button?.getBoundingClientRect();
          const visible =
            !!button &&
            !!box &&
            box.width > 0 &&
            box.height > 0 &&
            getComputedStyle(button).visibility !== 'hidden';
          return {
            evaluated: !!w.__deckEvaluated,
            busy: document.querySelector(busy) !== null,
            enabledClass: visible ? button.className : null,
          };
        }
        """,
        %{enabled: @footer_button, busy: @busy_footer_button, arm: arm}
      )

    case result do
      {:ok, %{"evaluated" => evaluated, "busy" => busy} = snapshot} ->
        enabled_class = snapshot["enabledClass"]

        %{
          evaluated: evaluated,
          busy: busy,
          enabled_class: if(is_binary(enabled_class), do: enabled_class)
        }

      _ ->
        nil
    end
  end

  defp role_of(%{enabled_class: nil}), do: nil

  defp role_of(%{enabled_class: class}) do
    if String.contains?(class, "closeFeedbackBtn"), do: :ack, else: :check
  end

  defp moved?(po, previous), do: screen_id(po) != previous or lesson_ended?(po)

  defp saw_evaluation(po, screen) do
    Agent.update(po.last_evaluation, fn _ -> %{screen: screen, at: now()} end)
  end

  defp quiet_for(po, screen) do
    case Agent.get(po.last_evaluation, & &1) do
      %{screen: ^screen, at: at} -> now() - at
      _ -> :infinity
    end
  end

  defp quiet_enough?(po, screen, timeout) do
    case quiet_for(po, screen) do
      :infinity -> true
      ms -> ms >= timeout
    end
  end

  # The role of a control advance() may click now, :changed once the screen
  # moves, or nil after give_up_at - at once when the deck is still evaluating
  # right after an :evaluating outcome, whose wait already covered it.
  defp await_control(po, previous, timeout, give_up_at, after_evaluating) do
    nav = po.page |> Page.locator(@canvas_nav_button) |> Locator.first()

    cond do
      moved?(po, previous) ->
        :changed

      true ->
        snapshot = deck_snapshot(po)

        result =
          cond do
            snapshot && snapshot.busy ->
              saw_evaluation(po, previous)
              if after_evaluating, do: {:return, nil}, else: :continue

            snapshot ->
              role =
                role_of(snapshot) ||
                  if(match?({:ok, true}, Locator.is_visible(nav)), do: :nav)

              cond do
                role == :ack -> {:return, role}
                role != nil and quiet_enough?(po, previous, timeout) -> {:return, role}
                true -> :continue
              end

            true ->
              :continue
          end

        case result do
          {:return, value} ->
            value

          :continue ->
            if now() > give_up_at do
              nil
            else
              Page.wait_for_timeout!(po.page, 200)
              await_control(po, previous, timeout, give_up_at, after_evaluating)
            end
        end
    end
  end

  # :changed once the screen moves; :settled on feedback the click produced
  # (for an acknowledgement, only after an evaluation). Otherwise waits at
  # least `timeout`, longer while the deck evaluates, up to `budget`, then
  # reports :evaluating if it saw an evaluation, else :timeout.
  defp wait_for_outcome(po, previous, timeout, budget, role) do
    do_wait_for_outcome(po, previous, timeout, budget, role, now() + timeout, false)
  end

  defp do_wait_for_outcome(po, previous, timeout, budget, role, deadline, saw_evaluating) do
    if moved?(po, previous) do
      :changed
    else
      snapshot = deck_snapshot(po)

      {saw_evaluating, deadline} =
        if snapshot do
          if snapshot.busy or (snapshot.evaluated and not saw_evaluating),
            do: saw_evaluation(po, previous)

          saw_evaluating = saw_evaluating or snapshot.evaluated or snapshot.busy

          deadline =
            if snapshot.busy, do: max(deadline, min(budget, now() + timeout)), else: deadline

          {saw_evaluating, deadline}
        else
          {saw_evaluating, deadline}
        end

      cond do
        snapshot && snapshot.enabled_class &&
          String.contains?(snapshot.enabled_class, "closeFeedbackBtn") &&
            (role != :ack or saw_evaluating) ->
          :settled

        now() >= deadline ->
          cond do
            moved?(po, previous) -> :changed
            saw_evaluating -> :evaluating
            true -> :timeout
          end

        true ->
          Page.wait_for_timeout!(po.page, 200)
          do_wait_for_outcome(po, previous, timeout, budget, role, deadline, saw_evaluating)
      end
    end
  end

  # ------------------------------------------------------------ inspection

  @doc """
  The lesson score shown in the deck header. Both the legacy and the themed
  header render it and the inactive one is hidden, so only the visible one
  is matched. Its text is the score with two decimals (e.g. "7.50").
  """
  def score(%{page: page}) do
    page
    |> Page.locator(".theme-header-score__value, .nameScoreButtonWrapper .score")
    |> Locator.filter(visible: true)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
