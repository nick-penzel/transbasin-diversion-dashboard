// Widgets drawn while their tab was hidden size themselves too small;
// nudge them to re-measure when a tab is shown.
$(document).on("shown.bs.tab", function () {
  window.dispatchEvent(new Event("resize"));
});
$(document).on("shiny:sessioninitialized", function () {
  setTimeout(function () { window.dispatchEvent(new Event("resize")); }, 800);
});

// Story maps render only once scrolled near (lazy_map() in mod_story.R)
$(document).on("shiny:sessioninitialized", function () {
  var els = document.querySelectorAll("[data-seen-input]");
  var seen = function (el) { Shiny.setInputValue(el.dataset.seenInput, true); };
  if (!("IntersectionObserver" in window)) { els.forEach(seen); return; }
  var obs = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (!e.isIntersecting) return;
      seen(e.target);
      obs.unobserve(e.target);
    });
  }, { rootMargin: "800px 0px" });
  els.forEach(function (el) { obs.observe(el); });
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

// River basins page: bring the clicked feature's card into view
$(document).on("shiny:connected", function () {
  Shiny.addCustomMessageHandler("scroll_into_view", function (id) {
    var el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "nearest" });
  });
});
