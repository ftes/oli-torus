defmodule OliE2E.Torus.CourseAuthoring.SimpleAuthorPersistenceTest do
  # Simple Author save diagnostics @pr
  use OliE2E.Case, async: true

  alias OliE2E.Pom.SimpleAuthor
  alias Playwright.{Page, Route}

  @moduletag :pr
  # These page-object checks intercept browser requests and need no Torus server
  # or seeded data. Replace the shared fixture's automatic site navigation.
  @moduletag site: false

  @origin "http://simple-author.test"
  @save_url "#{@origin}/api/v1/project/save-test/resource/1"

  setup %{page: page} do
    Page.route!(page, "#{@origin}/", fn route ->
      Route.fulfill!(route,
        content_type: "text/html",
        body: "<!doctype html><title>Save checks</title>"
      )
    end)

    Page.goto!(page, "#{@origin}/")
    :ok
  end

  defp save(page) do
    Page.evaluate!(
      page,
      """
      async (url) => {
        try {
          const response = await fetch(url, { method: 'PUT', body: '{}' });
          await response.text();
        } catch {
          // The page object, rather than fetch, must report transport failures.
        }
      }
      """,
      @save_url
    )
  end

  # `await expect(editor.waitForSaves(...)).rejects.toThrow(message)`
  defp assert_wait_for_saves_rejects(editor, message, args \\ []) do
    error =
      assert_raise RuntimeError, fn -> apply(SimpleAuthor, :wait_for_saves, [editor | args]) end

    assert error.message =~ message
  end

  test "accepts successful saves", %{page: page} do
    editor = SimpleAuthor.new(page)
    Page.route!(page, @save_url, fn route -> Route.fulfill!(route, status: 204) end)

    save(page)

    SimpleAuthor.wait_for_saves(editor)
  end

  test "reports HTTP errors even though the request completes", %{page: page} do
    editor = SimpleAuthor.new(page)

    Page.route!(page, @save_url, fn route ->
      Route.fulfill!(route, status: 500, body: "Save failed")
    end)

    save(page)

    assert_wait_for_saves_rejects(editor, "PUT #{@save_url}: HTTP 500")
    # A later call must not turn an earlier failed save into apparent success.
    assert_wait_for_saves_rejects(editor, "PUT #{@save_url}: HTTP 500")
  end

  test "reports aborted saves with the URL and network reason", %{page: page} do
    editor = SimpleAuthor.new(page)
    Page.route!(page, @save_url, fn route -> Route.abort(route, "failed") end)

    save(page)

    assert_wait_for_saves_rejects(editor, "PUT #{@save_url}: net::ERR_FAILED")
  end

  test "keeps unfinished saves pending until they complete", %{page: page} do
    editor = SimpleAuthor.new(page)

    Page.route!(page, @save_url, fn route ->
      try do
        assert_wait_for_saves_rejects(editor, "(1 pending)", [100])
      after
        Route.fulfill!(route, status: 204)
      end
    end)

    save(page)
    SimpleAuthor.wait_for_saves(editor)
  end
end
