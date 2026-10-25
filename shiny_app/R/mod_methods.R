# Methods tab: the running methods book. Each chapter is a Markdown file in
# methods/ named NN-slug.md (readable on GitHub too); figures sit in
# methods/figures/ and are served at methods-files/. Links with class
# "methods-link" anywhere in the app open a chapter and section (www/methods.js).

library(shiny)

#' Heading slug, matching GitHub's anchors for plain-text headings.
slugify <- function(x) gsub("^-+|-+$", "", gsub("[^a-z0-9]+", "-", tolower(x)))

#' Render one chapter's Markdown to HTML with heading ids and served image paths.
methods_html <- function(md) {
  html <- commonmark::markdown_html(paste(md, collapse = "\n"), extensions = TRUE)
  m <- gregexpr("<h([234])>(.*?)</h\\1>", html, perl = TRUE)
  regmatches(html, m) <- lapply(regmatches(html, m), \(h) {
    lvl <- substr(h, 3, 3)
    inner <- sub("^<h[234]>(.*)</h[234]>$", "\\1", h)
    sprintf('<h%s id="%s">%s</h%s>', lvl, slugify(gsub("<[^>]+>|&[a-z]+;", "", inner)), inner, lvl)
  })
  html <- gsub('src="figures/', 'src="methods-files/figures/', html, fixed = TRUE)
  gsub("<table>", '<div class="table-responsive"><table class="table table-sm">', html, fixed = TRUE) |>
    gsub(pattern = "</table>", replacement = "</table></div>", fixed = TRUE)
}

#' Chapters in file order: slug, title (the first "# " heading), and HTML.
methods_chapters <- function(dir = "methods") {
  files <- sort(list.files(dir, pattern = "^[0-9]+-.*\\.md$", full.names = TRUE))
  lapply(files, \(f) {
    md <- readLines(f, warn = FALSE, encoding = "UTF-8")
    list(slug = sub("^[0-9]+-", "", tools::file_path_sans_ext(basename(f))),
         title = sub("^# ", "", md[grep("^# ", md)[1]]),
         html = methods_html(md))
  })
}

methods_ui <- function(chapters) {
  panels <- lapply(chapters, \(ch) {
    nav_panel(ch$title, value = ch$slug, tags$article(class = "methods-doc", HTML(ch$html)))
  })
  tags$div(
    class = "methods-page",
    do.call(navset_pill_list, c(panels, list(id = "methods_nav", widths = c(3, 9), well = FALSE)))
  )
}
