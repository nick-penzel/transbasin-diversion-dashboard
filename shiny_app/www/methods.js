// Open a Methods chapter, then scroll to a section. Used by links with class
// "methods-link" (data-chapter, data-anchor) and by links between chapters
// written as "NN-slug.md#anchor" in the Markdown.
function openMethods(chapter, anchor) {
  var top = document.querySelector('.navbar a[data-value="methods"]');
  if (top) bootstrap.Tab.getOrCreateInstance(top).show();
  if (chapter) {
    var pill = document.querySelector('a[data-value="' + chapter + '"][data-bs-toggle]');
    if (pill) bootstrap.Tab.getOrCreateInstance(pill).show();
  }
  setTimeout(function () {
    var el = anchor && document.getElementById(anchor);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    else window.scrollTo({ top: 0 });
  }, 200);
}

$(document).on("click", "a.methods-link", function (e) {
  e.preventDefault();
  document.querySelectorAll(".popover").forEach(function (p) {
    var trigger = document.querySelector('[aria-describedby="' + p.id + '"]');
    if (trigger) bootstrap.Popover.getOrCreateInstance(trigger).hide();
  });
  openMethods(this.dataset.chapter, this.dataset.anchor);
});

$(document).on("click", ".methods-doc a[href]", function (e) {
  var href = this.getAttribute("href");
  var md = href.match(/^(?:\.\/)?[0-9]+-([a-z0-9-]+)\.md(?:#(.+))?$/);
  if (md) { e.preventDefault(); openMethods(md[1], md[2]); return; }
  if (href.charAt(0) === "#") { e.preventDefault(); openMethods(null, href.slice(1)); }
});
