# edge_admin/lib/edge_admin_web/live_dashboard_hooks.ex
defmodule EdgeAdminWeb.LiveDashboardHooks do
  @moduledoc """
  LiveDashboard `on_mount` hook that registers an `after_opening_head_tag`
  script with a CSP nonce.

  The Quantum dashboard renders timestamps as `<time class="qt-time"
  datetime="ISO_UTC">UTC text</time>`. This script wires up the `#quantum-tz-toggle`
  buttons (UTC / Local) and rewrites every `<time>` element's text content
  on click — without a server round-trip. A `MutationObserver` re-applies the
  active mode after every LiveView patch (the auto-refresh tick replaces the
  `<time>` elements with fresh server-rendered UTC text).

  This module exists because the admin's CSP (`script-src 'self'`) blocks
  inline scripts injected directly into a LiveDashboard page. Scripts injected
  via `register_after_opening_head_tag/2` carry the CSP nonce, so the browser
  allows them.
  """

  import Phoenix.Component, only: [sigil_H: 2]

  alias Phoenix.LiveDashboard.PageBuilder

  def on_mount(:default, _params, _session, socket) do
    {:cont, PageBuilder.register_after_opening_head_tag(socket, &quantum_tz_script/1)}
  end

  defp quantum_tz_script(assigns) do
    ~H"""
    <script nonce={@csp_nonces[:script]}>
      (function() {
        function applyTz(mode) {
          document.querySelectorAll('.quantum-page time.qt-time').forEach(function(el) {
            var iso = el.getAttribute('datetime');
            if (!iso) return;
            var text;

            if (mode === 'local') {
              var d = new Date(iso);
              if (!isNaN(d)) text = d.toLocaleString();
            }

            text = text || iso.replace('T', ' ').replace(/\.\d+Z$|Z$/, '');
            if (el.textContent !== text) el.textContent = text;
          });
        }

        function setMode(button) {
          var toggle = button.closest('#quantum-tz-toggle');
          var mode = button.getAttribute('data-tz');

          window.__quantumTzMode = mode;
          toggle.querySelectorAll('button').forEach(function(b) { b.classList.remove('active'); });
          button.classList.add('active');
          applyTz(mode);
        }

        function init() {
          applyTz(window.__quantumTzMode || 'UTC');

          // LiveView replaces the dashboard page during refreshes. Delegate
          // from document so newly-rendered timezone buttons stay interactive.
          if (!window.__quantumTzClickBound) {
            window.__quantumTzClickBound = true;

            document.addEventListener('click', function(event) {
              if (!(event.target instanceof Element)) return;

              var button = event.target.closest('#quantum-tz-toggle button[data-tz]');
              if (button) setMode(button);
            });
          }

          // Reapply the selected mode after LiveView patches in fresh <time>
          // elements. The observer is intentionally global because this script
          // lives in <head>, while the Quantum page is patched below <body>.
          if (!window.__quantumTzObserver) {
            window.__quantumTzObserver = new MutationObserver(function() {
              applyTz(window.__quantumTzMode || 'UTC');
            });

            window.__quantumTzObserver.observe(document.body, {
              childList: true,
              subtree: true
            });
          }
        }

        // Script is injected in <head>; defer until <body> exists.
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', init);
        } else {
          init();
        }
      })();
    </script>
    """
  end
end
