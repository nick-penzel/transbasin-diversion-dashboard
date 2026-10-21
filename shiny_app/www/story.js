// Widgets drawn while their tab was hidden size themselves too small;
// nudge them to re-measure when a tab is shown.
$(document).on("shown.bs.tab", function () {
  window.dispatchEvent(new Event("resize"));
});
$(document).on("shiny:sessioninitialized", function () {
  setTimeout(function () { window.dispatchEvent(new Event("resize")); }, 800);
});
