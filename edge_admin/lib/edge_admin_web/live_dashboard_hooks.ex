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
            if (mode === 'local') {
              var d = new Date(iso);
              if (!isNaN(d)) { el.textContent = d.toLocaleString(); return; }
            }
            el.textContent = iso.replace('T', ' ').replace(/\.\d+Z$|Z$/, '');
          });
        }

        function bind() {
          var toggle = document.getElementById('quantum-tz-toggle');
          if (!toggle || toggle.dataset.bound) return;
          toggle.dataset.bound = '1';
          toggle.querySelectorAll('button').forEach(function(btn) {
            btn.addEventListener('click', function() {
              var mode = btn.getAttribute('data-tz');
              window.__quantumTzMode = mode;
              toggle.querySelectorAll('button').forEach(function(b) { b.classList.remove('active'); });
              btn.classList.add('active');
              applyTz(mode);
            });
          });
        }

        function init() {
          bind();
          applyTz(window.__quantumTzMode || 'UTC');
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
