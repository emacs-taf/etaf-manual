# Grids and Character Surfaces

Three catalog components give applications fixed-geometry character surfaces: a tile grid whose cells project coordinate callbacks, a text grid of independently retained fixed-width text rows, and a playing card whose intrinsic dimensions never stretch to fill a viewport. They own layout and activation, never the caller's board, board state, timers or game rules, and their dimensions stay what the caller declared even when the window changes. [Images](images.md) defines the image Host the cells use, [UI Overview](ui-overview.md) the shared contract, and [Grid Layout](grid-layout.md) the underlying track model.

## The tile grid

<!-- index: etaf-tile-grid; coordinate callbacks; fixed cells; cell image -->

#### Component: etaf-tile-grid (&key rows columns cell-width cell-height cell-background cell-color cell-text cell-label cell-image cell-ref on-cell-press on-cell-focus)

Render ROWS by COLUMNS fixed cells with stable coordinate identities.

**Arguments.** ROWS and COLUMNS are positive integers; CELL-WIDTH (character columns, default 2) and CELL-HEIGHT (text lines, default 1) are positive integers and stay fixed when the viewport changes. The callbacks receive zero-based ROW and COLUMN: CELL-BACKGROUND returns a color or nil; CELL-COLOR supplies the foreground (nil inherits); both may return deferred Theme tokens. CELL-TEXT returns one line fitting CELL-WIDTH (default a space). CELL-IMAGE returns a local file path, an Emacs image descriptor including generated SVG, or nil — an image fills the fixed cell through the image Host, nil uses CELL-TEXT instead, and source decoding failures use the image Host's placeholder. CELL-LABEL returns the accessible name and help text (default `"Cell r,c"`). CELL-REF returns a distinct Host reference per cell; omitted references are instance-local. ON-CELL-PRESS handles keyboard and mouse activation, and without it cells are read-only; ON-CELL-FOCUS reports the coordinates when focus enters a cell.

**Semantics.** The grid owns layout and activation, not board state or timers: it reads the caller's refs inside the callbacks so unchanged cells retain their content, and it never maintains a second selection. With a press callback every cell is a `button` with a Tab index inside a `grid` focus group; without one the cells are inert. Cells clip hidden overflow and center their content, and a focus outline marks the focused cell.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when ROWS, COLUMNS, CELL-WIDTH or CELL-HEIGHT is not a positive integer, or when one of the coordinate callbacks is neither a function nor nil. A CELL-TEXT or CELL-LABEL that is not a single line fitting the cell width also signals at render time.

**Example.**

```elisp
(etaf-tile-grid :rows 8 :columns 12 :cell-width 2 :cell-height 1
                :cell-text (lambda (_r _c) ".")
                :on-cell-press (lambda (row column) (select-cell row column)))
```

**See also.** `etaf-text-grid`, [Images](images.md).

## The text grid

<!-- index: etaf-text-grid; fixed-width rows; monospace surface -->

#### Component: etaf-text-grid (&key rows columns row-text row-ref label)

Display ROWS fixed text lines, each COLUMNS character columns wide.

**Arguments.** ROWS and COLUMNS are positive integers. ROW-TEXT is a required callback receiving the zero-based row; it returns a single-line string whose display width fits COLUMNS, and short rows are padded with spaces. ROW-REF optionally returns distinct Text Host references for retained content updates — those updates must also fit and pad to COLUMNS, with the callback's state kept in sync. LABEL names the read-only surface (default `"Text grid"`).

**Semantics.** Each row keeps a stable identity and its own retained boundary, so a change to one row's text repaints one line instead of the whole surface. The component has no focus targets, input handling, timers or terminal escape interpretation; it is a monospaced display, and wide characters occupy their Emacs display width. Individually retained rows are what a caller with a finer-grained identity uses instead of one big text host.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when ROWS or COLUMNS is not a positive integer, ROW-TEXT is not a function, ROW-REF is neither a function nor nil, or LABEL is not a string. At render time a row content that is not a string, contains a newline, carriage return or tab, or is wider than COLUMNS signals the same condition naming ROW-TEXT.

**Example.**

```elisp
(etaf-text-grid :rows 24 :columns 80 :row-text (lambda (row) (buffer-line row)))
```

**See also.** `etaf-tile-grid`.

## The playing card

<!-- index: etaf-playing-card; card face; pile placeholder; intrinsic size -->

#### Component: etaf-playing-card (&key rank suit face-down empty selected disabled on-press label ref columns lines)

Present a controlled playing card or empty pile as one activation target.

**Arguments.** RANK is a one-line string up to three columns; SUIT is `spades`, `hearts`, `clubs`, `diamonds` or nil. FACE-DOWN conceals the rank and suit, including the generated accessible label. EMPTY presents a pile placeholder. SELECTED changes the paint without changing geometry. COLUMNS defaults to 9 with a minimum of 7, and LINES to 5 with a minimum of 1; one row exposes just a card's corner in a stack. These intrinsic dimensions never stretch to fill a viewport. ON-PRESS receives no arguments; omitted or disabled cards are noninteractive. LABEL overrides the accessible name and help, so callers must not put hidden information there.

**Semantics.** The card is one centered button sized in cells: a top corner with the rank and suit glyph, a centered suit mark (or a `◇` when face-down), and a bottom corner that appears when the card is more than three rows tall. Colors come from the playing-card tokens — a warm ivory face for the default bg, black or red ink depending on the suit, the blue back for face-down cards, a muted placeholder for an empty pile, the amber selected background and the hover tint — so a game can restyle the table through its Theme. Hover preserves every glyph and covers the complete painted card. Face-down cards and empty piles derive a subtle tint from their own surface instead of borrowing the face-up hover fill; selected cards suppress hover paint. The caller owns selection, stacks, moves and rules, and no game backend is required.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when RANK is neither nil nor a one-line string of at most three columns, SUIT is not one of the four suits or nil, COLUMNS is below 7, or LINES is below 1.

**Example.**

```elisp
(etaf-playing-card :rank "A" :suit 'hearts :on-press #'play-card)
```

## Playing-card tokens

<!-- index: ui-playing-card-bg; ui-playing-card-red; ui-playing-card-back-bg -->

#### Token: :ui-playing-card-bg

The face background of an ordinary card.

#### Token: :ui-playing-card-black

The ink of a spades or clubs card.

#### Token: :ui-playing-card-red

The ink of a hearts or diamonds card.

#### Token: :ui-playing-card-back-bg

The background of a face-down card.

#### Token: :ui-playing-card-back-fg

The front color of a face-down card.

**Semantics.** The face pair paints the concealed card; a face-down card never leaks its rank or suit through paint, text or the accessible label.

#### Token: :ui-playing-card-empty-bg

The background of an empty pile placeholder.

#### Token: :ui-playing-card-empty-fg

The glyph color of an empty pile placeholder.

#### Token: :ui-playing-card-selected-bg

The background of a selected card.

#### Token: :ui-playing-card-hover-bg

The hover tint of an interactive card.

**Semantics.** Selection and hover are paint only — the card's geometry and the pile's layout never move — and every token falls back to the catalog's built-in palette when no Theme is provided.

## Errors and recovery

- `error→ etaf-component-call-error` reports every rejected input through `etaf-check-prop`: a non-positive dimension, a callback that is not a function, a row content that is not a single line fitting its column count, a card rank that is too wide, an unknown suit and a card narrower than seven columns.
- The grids own no state to roll back: a rejected callback result fails the render and the previously published cells or rows stay on screen.
- A tile image that cannot be decoded follows the image Host's placeholder path rather than failing the grid; a nil image simply falls back to the cell text.
- The playing card is pure presentation: a press reports to the caller, and an ignored press leaves the card exactly as it was.

**See also.** [UI Overview](ui-overview.md#errors-and-recovery), [Images](images.md).

```elisp :run
(etaf-view
 (column :item-gap '(lh 1)
   (etaf-tile-grid :rows 2 :columns 4 :cell-width 3 :cell-height 1
                   :cell-text (lambda (row column) (format "%d%d" row column))
                   :on-cell-press #'ignore)
   (etaf-playing-card :rank "A" :suit 'hearts :on-press #'ignore)))
```
