defmodule OliE2E.Core.CaptchaTest do
  # captcha submission boundary @pr
  use OliE2E.Case, async: true

  @moduletag :pr
  # imports `test` from '@playwright/test', not the my-fixture one
  @moduletag plain: true

  alias Playwright.{Page, Promise, Request, Route}

  @origin "http://torus.test"
  @token "fixture-only-captcha-token"
  @field "g-recaptcha-response"

  setup %{context: context, page: page} do
    OliE2E.Captcha.configure(context, @origin, @token)

    Page.route!(page, "http://torus.test/**", fn route ->
      Route.fulfill!(route,
        content_type: "text/html",
        body:
          ~s|<form id="protected" method="post" action="/submit"><div class="g-recaptcha"></div><input name="email" value="test@example.test"><button>Submit</button></form>|
      )
    end)

    Page.goto!(page, @origin)
    :ok
  end

  test "native POST carries the token without adding a field", %{page: page} do
    Expect.to_have_count!(Page.locator(page, ~s|[name="#{@field}"]|), 0)
    request = Page.wait_for_request(page, fn request -> Request.method(request) == "POST" end)
    Page.get_by_role(page, :button) |> Locator.click!()
    post_data = Promise.await!(request) |> Request.post_data()
    assert URI.decode_query(post_data)[@field] == @token
  end

  test "LiveView FormData includes one token after form replacement without changing the DOM",
       %{page: page} do
    result =
      Page.evaluate!(page, """
      () => {
        document.querySelector('form').outerHTML =
          '<form phx-submit="save"><div phx-hook="Recaptcha"></div><input name="g-recaptcha-response" value="stale"></form>';
        const form = document.querySelector('form');
        const before = form.outerHTML;
        const data = new FormData(form);
        return {
          values: data.getAll('g-recaptcha-response'),
          unchanged: before === form.outerHTML,
          nativeInstance: data instanceof FormData,
        };
      }
      """)

    assert result == %{"values" => [@token], "unchanged" => true, "nativeInstance" => true}
  end

  for submission <- ["requestSubmit", "submit"] do
    test "native GET on a LiveView form never receives a token via #{submission}", %{page: page} do
      request =
        Page.wait_for_request(page, fn request ->
          URI.parse(Request.url(request)).path == "/submit"
        end)

      Page.locator(page, "form")
      |> Locator.evaluate!(
        """
        (form, submission) => {
          form.removeAttribute('method');
          form.setAttribute('phx-submit', 'save');
          form[submission]();
        }
        """,
        unquote(submission)
      )

      url = Promise.await!(request) |> Request.url()
      refute URI.decode_query(URI.parse(url).query || "") |> Map.has_key?(@field)
    end
  end

  for attributes <- [
        ~s|type="submit" formaction="https://external.test/"|,
        ~s|type="submit" formmethod="get"|,
        ~s|type="image" formaction="https://external.test/"|,
        ~s|type="image" formmethod="get"|
      ] do
    test "withholds the token for an external submit control with #{attributes}", %{page: page} do
      values =
        Page.evaluate!(
          page,
          """
          (attributes) => {
            document.body.insertAdjacentHTML(
              'beforeend',
              `<input value="Override" alt="Override" form="protected" ${attributes}>`,
            );
            const form = document.querySelector('form');
            form.setAttribute('phx-submit', 'save');
            return new FormData(form).getAll('g-recaptcha-response');
          }
          """,
          unquote(attributes)
        )

      assert values == []
      request = Page.wait_for_request(page, &Request.is_navigation_request/1)

      Page.route!(page, "https://external.test/**", fn route ->
        Route.fulfill!(route, body: "external")
      end)

      Page.locator(page, ~s|input[form="protected"]|) |> Locator.click!()
      submitted = Promise.await!(request)
      refute Request.url(submitted) =~ @token
      refute (Request.post_data(submitted) || "") =~ @token
    end
  end

  test "withholds the token from external actions, unprotected forms and external frames",
       %{page: page} do
    values =
      Page.evaluate!(page, """
      () => {
        const form = document.querySelector('form');
        form.action = 'https://external.test/';
        const external = new FormData(form).get('g-recaptcha-response');
        form.action = '/submit';
        form.querySelector('.g-recaptcha').remove();
        return [external, new FormData(form).get('g-recaptcha-response')];
      }
      """)

    assert values == [:null, :null]

    Page.route!(page, "https://external.test/**", fn route ->
      Route.fulfill!(route,
        content_type: "text/html",
        body:
          ~s|<form method="post" action="#{@origin}/submit" phx-submit="save"><div class="g-recaptcha"></div></form>|
      )
    end)

    Page.evaluate!(page, """
    () => {
      const frame = document.createElement('iframe');
      frame.src = 'https://external.test/';
      document.body.append(frame);
    }
    """)

    form = Page.frame_locator(page, "iframe") |> Playwright.FrameLocator.locator("form")
    Expect.to_be_attached!(form)

    assert Locator.evaluate!(form, "(form) => new FormData(form).get('g-recaptcha-response')") ==
             :null
  end

  test "blocks Google script loading", %{page: page} do
    failed =
      Page.wait_for_event(page, :request_failed, fn request ->
        String.starts_with?(Request.url(request), "https://www.google.com/recaptcha/")
      end)

    Page.evaluate!(page, """
    () => {
      const script = document.createElement('script');
      script.src = 'https://www.google.com/recaptcha/api.js';
      document.head.append(script);
    }
    """)

    Promise.await!(failed)
  end
end
