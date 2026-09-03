(function () {
  // Matches the legacy Portal's Status/Index.cshtml: filter to the Kumo
  // (IU Cloud Storage) service, then group into Alert/Ongoing/Maintenance
  // sections with counts, and link out to the full ServiceNow history.
  // Legacy filtered by service *number* (BSN0001274); we filter by id, the
  // more stable identifier -- same service either way.
  var KUMO_SERVICE_ID = "3461ae821b9df8908b3999fabc4bcba7";
  var NOTICES_API = "https://servicenow.iu.edu/api/iuit/status/notices";
  var HISTORY_URL = "https://servicenow.iu.edu/status?id=iu_service_status&service=BSN0001274";
  var TYPE_ORDER = ["Alert", "Ongoing", "Maintenance"];

  function isCurrentlyVisible(notice, now) {
    var start = notice.visibleStart ? new Date(notice.visibleStart) : null;
    var end = notice.visibleEnd ? new Date(notice.visibleEnd) : null;
    if (start && now < start) return false;
    if (end && now > end) return false;
    return true;
  }

  function formatDate(iso) {
    return iso ? new Date(iso).toLocaleString() : "";
  }

  function noticeCard(n) {
    var dates = "Visible " + formatDate(n.visibleStart) + (n.visibleEnd ? " through " + formatDate(n.visibleEnd) : "");
    return (
      '<div class="status-notice status-notice--' + n.noticeType.toLowerCase() + '">' +
        '<div class="status-notice__header">' + n.name + '</div>' +
        '<div class="status-notice__content">' + n.content + '</div>' +
        '<div class="status-notice__dates">' + dates + '</div>' +
      '</div>'
    );
  }

  function typeSection(type, notices) {
    var body = notices.length
      ? notices.map(noticeCard).join("")
      : '<p class="status-ok">No known service interruptions at this time.</p>';
    // Auto-expand a section only when it actually has something to show.
    return (
      '<details class="status-section"' + (notices.length ? " open" : "") + '>' +
        '<summary>' + type + ' <span class="status-count">' + notices.length + '</span></summary>' +
        body +
      '</details>'
    );
  }

  function renderNotices(notices) {
    var container = document.getElementById("kumo-storage-notices");
    var historyLink =
      '<div class="status-banner status-banner--info">Complete notice history is available ' +
      '<a href="' + HISTORY_URL + '" target="_blank" rel="noopener">here</a>.</div>';

    if (!notices.length) {
      container.innerHTML =
        '<div class="status-banner status-banner--ok">No known service interruptions at this time. If you’re experiencing an issue, ' +
        '<a href="mailto:kumo@iu.edu">reach out to us</a>.</div>' + historyLink;
      return;
    }

    var byType = {};
    notices.forEach(function (n) {
      (byType[n.noticeType] = byType[n.noticeType] || []).push(n);
    });
    var html = TYPE_ORDER.map(function (t) { return typeSection(t, byType[t] || []); }).join("");
    container.innerHTML = html + historyLink;
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

  loadNotices();
})();
