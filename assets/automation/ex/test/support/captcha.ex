defmodule OliE2E.Captcha do
  @moduledoc "Port of src/core/captcha.ts."

  alias Playwright.BrowserContext

  @script """
  ({ origin, token }) => {
    if (location.origin !== origin) return;

    const eligible = (form) => {
      if (
        !form.querySelector('.g-recaptcha, [phx-hook="Recaptcha"]') ||
        new URL(form.action).origin !== origin
      ) {
        return false;
      }

      // FormDataEvent has no submitter. Reject unsafe overrides on any
      // associated control, including external controls and image submitters
      // (which browsers omit from form.elements).
      return Array.from(document.querySelectorAll('button, input')).every((control) => {
        if (
          !(control instanceof HTMLButtonElement || control instanceof HTMLInputElement) ||
          control.form !== form
        ) {
          return true;
        }
        return (
          (!control.hasAttribute('formaction') ||
            new URL(control.formAction).origin === origin) &&
          (!control.hasAttribute('formmethod') || control.formMethod === 'post')
        );
      });
    };

    document.addEventListener(
      'formdata',
      (event) => {
        const form = event.target;
        if (form instanceof HTMLFormElement && form.method === 'post' && eligible(form)) {
          event.formData.set('g-recaptcha-response', token);
        }
      },
      true,
    );

    // LiveView serializes with new FormData(form). Actionless LiveView forms
    // default to GET: add the token only to the JS result, never to native GET
    // submission (including form.submit(), which bypasses submit listeners).
    window.FormData = new Proxy(window.FormData, {
      construct(target, args, newTarget) {
        const data = Reflect.construct(target, args, newTarget);
        const [form] = args;
        if (
          form instanceof HTMLFormElement &&
          form.hasAttribute('phx-submit') &&
          eligible(form)
        ) {
          data.set('g-recaptcha-response', token);
        }
        return data;
      },
    });
  }
  """

  @doc """
  Supply the private automation credential without changing captcha markup or
  deploying a client substitute. Call before creating pages in custom contexts.
  """
  def configure(context, base_url, token \\ OliE2E.Env.captcha_token()) do
    BrowserContext.route!(
      context,
      fn uri ->
        uri.host in ["www.google.com", "www.recaptcha.net", "www.gstatic.com"] and
          String.starts_with?(uri.path || "", "/recaptcha/")
      end,
      fn route -> Playwright.Route.abort(route) end
    )

    if token not in [nil, ""] do
      uri = URI.parse(base_url)

      origin =
        "#{uri.scheme}://#{uri.host}" <>
          if(uri.port in [80, 443, nil], do: "", else: ":#{uri.port}")

      BrowserContext.add_init_script!(context, @script, %{origin: origin, token: token})
    end

    :ok
  end
end
