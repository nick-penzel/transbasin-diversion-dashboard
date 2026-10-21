// Widgets drawn while their tab was hidden size themselves too small;
// nudge them to re-measure when a tab is shown.
$(document).on("shown.bs.tab", function () {
  window.dispatchEvent(new Event("resize"));
});
$(document).on("shiny:sessioninitialized", function () {
  setTimeout(function () { window.dispatchEvent(new Event("resize")); }, 800);
});

// Highlight the chapter in view in the side table of contents
$(document).on("shiny:sessioninitialized", function () {
  var links = document.querySelectorAll(".story-toc a");
  if (!links.length || !("IntersectionObserver" in window)) return;
  var obs = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (!e.isIntersecting) return;
      links.forEach(function (a) {
        a.classList.toggle("active", a.dataset.target === e.target.id);
      });
    });
  }, { rootMargin: "-45% 0px -50% 0px" });
  document.querySelectorAll(".story .chapter").forEach(function (c) { obs.observe(c); });
});
