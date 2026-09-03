(function () {
  // Portal has no CORS-open /health endpoint (yet), so we can't read a real
  // status code cross-origin. Instead we probe a known public Portal page in
  // no-cors mode: the browser still sends the request, and the fetch promise
  // resolves as soon as *any* response comes back, even though we can't read
  // it -- only a network-level failure (DNS, connection refused, timeout)
  // makes it reject. That's enough to answer "is Portal reachable at all,"
  // just not "is every feature on it working."
  var PROBE_URL = "https://cloudstorage.iu.edu/Home/Faq";
  var TIMEOUT_MS = 8000;

  function render(reachable) {
    var container = document.getElementById("kumo-portal-health");
    if (reachable) {
      container.innerHTML = '<div class="status-banner status-banner--ok">Kumo Portal is reachable.</div>';
    } else {
      container.innerHTML =
        '<div class="status-banner status-banner--down">Kumo Portal doesn’t appear to be reachable right now. If this persists, ' +
        '<a href="mailto:kumo@iu.edu">reach out to us</a>.</div>';
    }
  }

  var controller = new AbortController();
  var timer = setTimeout(function () { controller.abort(); }, TIMEOUT_MS);

  fetch(PROBE_URL, { mode: "no-cors", cache: "no-store", signal: controller.signal })
    .then(function () {
      clearTimeout(timer);
      render(true);
    })
    .catch(function () {
      clearTimeout(timer);
      render(false);
    });
})();
