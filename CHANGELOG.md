# Changelog

All notable changes to the ETAF Reference Manual and the `etaf-manual` package are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- The Emacs manual reader: `etaf-manual-open`, `etaf-manual-close` and
  `etaf-manual-lookup`, plus the headless session API
  (`etaf-manual-reader-create`, `etaf-manual-reader-state`,
  `etaf-manual-reader-view` and the navigation functions).  The reader shows
  an adaptive two-column layout with a collapsible navigation column,
  definition cards, language and palette switches, an index jump, and
  runnable examples that render in place with source, preview and
  side-by-side modes.  Every line keeps the standard line height, so
  scrolling never shifts the layout.  The reader's keys are declared on the page Host as
  `:keys', so `?' opens the ETAF key help listing them with their labels.
  A long chapter shows its first sections at once and appends the rest while
  Emacs is idle; a lookup renders through its entry immediately.
- Reader navigation and search: `/` searches the whole book and `M-n` /
  `M-p` walk the matching sections; `i` opens a jump completion over every
  chapter, section, definition entry and index term
  (`etaf-manual-reader-jump-targets`); and a code span in the article whose
  text names a definition entry links to that entry, so `RET` or a click
  over it opens the definition.  `etaf-manual-reader-search`,
  `etaf-manual-reader-search-next`, `etaf-manual-reader-search-previous`
  and `etaf-manual-reader-search-match` drive the same search headlessly,
  and `etaf-manual-lookup` starts from the symbol at point when it has an
  entry.
- Reader browsing: the navigation column lists the parts, chapters and
  level-2 sections; a frame wide enough for a third column shows an
  on-this-page outline that marks the current section; each chapter ends
  with previous/next chapter cards; and the reader remembers its reading
  position across sessions (`etaf-manual-reader-position-file',
  `etaf-manual-reader-remember', `etaf-manual-reader-restore').
- The generated concept index groups terms under symbols and A–Z, filing
  Chinese terms by the Pinyin of their first character; the symbol index
  groups functions, macros, variables, hooks and errors by package and the
  other entries by kind.
- The Introduction and the Reactivity chapter in English and Simplified Chinese.
- The `etaf-manual` package: `etaf-manual-book`, `etaf-manual-definition`, `etaf-manual-example-view`, the `etaf-manual-language` option and the `etaf-manual-error` condition.
- A gate that checks the book against the provider packages: signatures, public names, versions, links, coverage, translation structure and one line per paragraph. Runnable examples are mounted by the acceptance tests.
