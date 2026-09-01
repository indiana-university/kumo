(function () {
  var KUMO_SERVICE_ID = "3461ae821b9df8908b3999fabc4bcba7";
  var NOTICES_API = "https://servicenow.iu.edu/api/iuit/status/notices";
  // No public Kumo Portal /health endpoint exists yet (tracked in
  // Kumo-Server-Blazor) -- leave blank until one does, so this degrades to
  // "not available yet" instead of failing.
  var PORTAL_HEALTH_URL = "";

  function renderNotices(notices) {
    var container = document.getElementById("kumo-storage-notices");
    if (!notices.length) {
      container.innerHTML = '<p class="status-ok">No active notices for IU Cloud Storage.</p>';
      return;
    }
    var html = notices
      .map(function (n) {
        return (
          '<div class="status-notice status-notice--' + n.noticeType.toLowerCase() + '">' +
            '<div class="status-notice__header">' +
              '<span class="status-notice__type">' + n.noticeType + '</span>' +
              '<span class="status-notice__name">' + n.name + '</span>' +
            '</div>' +
            '<div class="status-notice__content">' + n.content + '</div>' +
          '</div>'
        );
      })
      .join("");
    container.innerHTML = html;
  }

  function isCurrentlyVisible(notice, now) {
    var start = notice.visibleStart ? new Date(notice.visibleStart) : null;
    var end = notice.visibleEnd ? new Date(notice.visibleEnd) : null;
    if (start && now < start) return false;
    if (end && now > end) return false;
    return true;
  }

  function loadNotices() {
    var container = document.getElementById("kumo-storage-notices");
    fetch(NOTICES_API)
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (notices) {
        var now = new Date();
        var relevant = notices.filter(function (n) {
          if (n.status !== "Published") return false;
          var inService = (n.services || []).some(function (s) { return s.id === KUMO_SERVICE_ID; });
          return inService && isCurrentlyVisible(n, now);
        });
        renderNotices(relevant);
      })
      .catch(function () {
        container.innerHTML = '<p class="status-error">Couldn’t load IU status notices right now. Try reloading the page.</p>';
      });
  }

  function loadPortalHealth() {
    var container = document.getElementById("portal-health");
    if (!PORTAL_HEALTH_URL) {
      container.innerHTML = '<p class="status-unknown">Live Portal status isn’t available yet.</p>';
      return;
    }
    fetch(PORTAL_HEALTH_URL, { cache: "no-store" })
      .then(function (res) {
        container.innerHTML = res.ok
          ? '<p class="status-ok">Kumo Portal is reachable.</p>'
          : '<p class="status-down">Kumo Portal returned an error (HTTP ' + res.status + ').</p>';
      })
      .catch(function () {
        container.innerHTML = '<p class="status-down">Kumo Portal appears to be unreachable.</p>';
      });
  }

  loadNotices();
  loadPortalHealth();
})();
