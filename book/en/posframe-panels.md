# Floating Panels

A panel is a child frame that hosts one ETAF Runtime above the window you are working in: a clock, a player, a timer, a search result. Panels are independent — each owns its frame, Runtime and input, several can be open at once, and a panel never changes the selected buffer. A focusable panel can take the keyboard; a click anywhere on a panel raises it above the other panels. This chapter documents the panel surface itself; [Panel Applications](posframe-applications.md) documents the registry that opens a whole application as a panel, [Component Styles and Themes](component-styles-and-themes.md) the Theme plist a panel provides to its Views, [Focus](focus.md) and [Keyboard](keyboard.md) the input a focusable panel receives, and [Positioning, Layers and Overlays](positioning-layers-and-overlays.md) the absolute coordinates a panel is placed at.

## Opening, refreshing and closing

<!-- index: etaf-posframe-show; etaf-posframe-hide; etaf-posframe-toggle; panel options; panel identity -->

#### Function: etaf-posframe-show (view &rest options)

Show VIEW in a floating panel and return the panel.

**Arguments.** VIEW is a View or a zero-argument function returning one; it is mounted fresh for this panel and receives its own Runtime, and the panel follows the current buffer at call time. OPTIONS is a plist: `:at` placement, an anchor such as `frame-top-right`, `window-center` or `point`, `(ANCHOR ROWS COLS)` to shift an anchor by character cells where negative rows go up and columns left, `(cells ROW COL)` for a character cell of the current window, `(pixels X . Y)` for frame pixels, or a Posframe poshandler, default `point`; `:stack` keeps a panel clear of the live panels at the same anchor, stacking downward from a top or centre anchor and upward from a bottom one; `:width` is content columns, `etaf-posframe-default-width` by default, or `(fraction 0.5)` for half the parent frame's width, clamped to the parent frame; `:height` is a row budget, `etaf-posframe-default-max-height` by default, or `(fraction 0.5)` for half the parent frame's height, and taller content clips; `:fill-height` keeps the frame at the row budget instead of shrinking to the content; `:title` is the title-bar text, and without it the panel has no header line and cannot be dragged; `:draggable` moves the panel by dragging that title bar; `:focusable` lets the panel take the keyboard so its View's `:keys`, text inputs and buttons receive input; `:focus-on-open` selects the panel on open and defaults to `:focusable`; `:auto-hide` is nil to keep the panel until it is closed, t to hide it when the user works elsewhere, or a number of seconds; `:theme` is `auto` to follow the Emacs theme, `light` or `dark` to pin the palette, or a Theme plist; `:border` is the frame border plist documented in [Appearance and borders](#appearance-and-borders); and `:key` is the panel's identity.

**Semantics.** A panel is a frame plus a mounted Runtime, so the View inside it behaves exactly as it does in a buffer: refs, Components, keys and retained updates all work, and the panel adds only the frame, the title bar and the pointer handling around them. Showing a View with a `:key` that is already live replaces that panel; different keys keep their own frame, Runtime and position, which is what lets two timers sit side by side. A frame resized from outside becomes the panel's new width or height, and the View re-lays out at it instead of being snapped back.

**Returns.** A panel value, opaque to callers; pass it to the functions below.

**Errors.** `etaf-posframe-error` for an unknown option, an invalid anchor or a non-graphical frame. A failed show unmounts the View and deletes the frame before the error is re-signaled.

**Example.**

```elisp
(etaf-posframe-show (etaf-view (text "25:00"))
                    :key 'timer :title "Timer" :width 24 :height 2
                    :at 'frame-top-right :stack t :draggable t)
```

#### Function: etaf-posframe-hide (&optional panel)

Hide PANEL and release its Runtime, timer and frame.

**Semantics.** PANEL defaults to the newest panel of the current buffer, which is what the panel's own keys call, and other panels stay open. Hiding releases everything the panel owned, so a hidden panel costs nothing until it is shown again. It is safe to call repeatedly, and it returns non-nil only when a live panel was hidden.

**Returns.** Non-nil when a live panel was hidden.

**See also.** `etaf-posframe-show`, `etaf-posframe-toggle`, `etaf-posframe-app`.

#### Function: etaf-posframe-toggle (view &rest options)

Hide the panel of the same `:key`, or show VIEW with OPTIONS.

**Semantics.** Without `:key` this is the newest panel of the current buffer. It is the entry for a key binding that opens and closes the same panel without touching the others, and it accepts every option `etaf-posframe-show` does. Because the panel is replaced rather than reused, the View is mounted fresh on each open, so it reads the state of the application at that moment.

**Returns.** The new panel, or nil when it hid one.

**See also.** `etaf-posframe-show`, `etaf-posframe-hide`.

#### Function: etaf-posframe-refresh (&optional panel)

Schedule PANEL to re-lay out at its frame width and fit the frame to the rendered content.

**Semantics.** PANEL defaults to the current buffer's panel. A frame resized from outside becomes the panel width, so the View reflows and the title bar repaints to the new column count; the fit is deferred past the current event and render, so it is safe to call from a Button, a timer or a theme callback. A panel also re-fits automatically when its host frame changes size, so the call is only needed after content changed height without a Runtime update. The panel's fit backs off when it keeps resizing, so a condition that fights the fit cannot run away with the CPU.

**Returns.** Non-nil when PANEL is live.

## Reading the open panels

<!-- index: etaf-posframe-panels; etaf-posframe-panel-frame; etaf-posframe-live-p -->

#### Function: etaf-posframe-panels ()

Return the live panels, most recent first.

**Semantics.** The list is a copy, so a caller may hide panels while walking it. Order is recency, which is what `etaf-posframe-hide` uses for its default and what `etaf-posframe-cycle` walks.

**Returns.** A list of panel values.

#### Function: etaf-posframe-panel-frame (panel)

Return PANEL's child frame, or nil when PANEL is not live.

**Semantics.** Read or compare the frame with this instead of reaching into package internals, for example to place another panel relative to it or to record a window id for a screenshot.

**Returns.** A frame or nil.

**See also.** `etaf-posframe-live-p`.

#### Function: etaf-posframe-live-p (panel)

Return non-nil while PANEL's frame exists and its Runtime is mounted.

**Semantics.** A panel value outlives the panel: holding it after the panel is hidden is safe, and this predicate says whether there is still something to talk to.

**Returns.** A boolean.

## Placement

<!-- index: panel anchor; panel stacking; character cell placement -->

An anchor name places the panel relative to the parent frame or the current window, and a shifted anchor moves it by character cells so a panel can sit beside a word instead of covering it. A character cell or a pixel pair places it exactly, which is what a panel that follows the pointer or a recorded position needs. `:stack` reads the live panels at the same anchor and moves the new one clear of them, so a series of panels opened with one key stacks instead of covering each other. Panels are child frames, so they are positioned in frame pixels and do not take part in window layout.

## The title bar and the pointer

<!-- index: panel title bar; panel theme toggle; panel hover border; panel drag -->

A panel with a `:title` has a full-width title bar: one row high, painted in the panel surface lifted slightly toward the foreground, with a hairline below it and the theme toggle at its right when the panel's `:theme` is a mode. The title bar clears the theme's own `header-line` face, so a light theme gets no dark outline around it. Dragging the title bar moves the panel when `:draggable` is set, which is Posframe's own drag and needs no code in the application.

The pointer never takes the keyboard. A panel leaves buffer-level `track-mouse` off, because Emacs then selects the frame under the pointer whenever it moves, and leaving a panel would take the keyboard with the pointer. The hover border reads the pointer from a short timer instead: the panel under the pointer paints its border in the accent, and only a click moves the keyboard. A panel that is already focused keeps its focused border and takes no hover paint, so the two states never stack.

The theme toggle in the title bar is the `亮`, `随` and `暗` row documented in [Buttons and Choice Controls](ui-buttons-and-choice-controls.md) as `etaf-toggle-strip`: the selected segment fills with the theme accent and the others keep the title-bar surface. A click repaints that panel on the chosen mode for the rest of its life; `:theme` stays the value the caller passed, so the choice is a session setting and never writes configuration. A panel with its own palette has no toggle.

## The keyboard

<!-- index: panel keys; panel focus; panel cycling -->

A panel is focusable only when it was opened with `:focusable`, and only then do its View's keys, text inputs and buttons receive input; clicking any part of a panel raises it above the other panels either way. `etaf-posframe-panel-keys` is always active while a focusable panel holds the keyboard and outranks the View's own keys for exactly its three bindings, so closing a panel never depends on the application remembering to bind it.

#### Variable: etaf-posframe-panel-keys

Keymap that is always active while a focusable panel has focus.

**Semantics.** It closes the panel on `q`, `ESC` and `C-g` and outranks the View's own keys only for those three bindings, so an application may use every other key freely. A View key that should win over these three is not possible: that is what keeps the panel closeable from any state, including a View whose key handling is stuck.

**See also.** `etaf-posframe-cycle`, `etaf-posframe-hide`.

#### Variable: etaf-posframe-hide-inactive

Hide the panels while Emacs is not the active application, t by default.

**Semantics.** A child frame is a window of its own, so a window manager that lists windows would offer the panel as a target and clicking it would activate Emacs instead of the application behind it. Hiding the panels while another application is active keeps that list clean; the panels come back when Emacs is active again.

#### Variable: etaf-posframe-focus-follows-mouse

Move the input focus to a panel the mouse pointer rests on, nil by default.

**Semantics.** Only panels that accept the keyboard are focused. The default keeps the keyboard where the user put it, which is why the hover border needs no option: the panel under the pointer paints its border accent and keeps the keyboard, and a click is what moves it.

**See also.** `etaf-posframe-show`, `etaf-posframe-panel-keys`.

## Appearance and borders

<!-- index: panel theme; panel palette; panel border; border strength -->

A panel provides a Theme to its Views, derived from the parent frame's default face, so an application painted inside it follows the user's palette instead of shipping colors. The panel frame paints the panel surface, and the title bar, the borders and the Views all read the same palette, which is why a light panel inside a dark frame stays light and readable.

#### Function: etaf-posframe-theme (&optional frame mode)

Return an ETAF UI Theme plist derived from FRAME's default face.

**Arguments.** FRAME defaults to the selected frame. MODE is `light` or `dark` to pin the palette to that mode, or nil to follow the frame. A pin that agrees with the frame's own surface keeps that surface, so switching between following the theme and pinning to the frame's own mode does not move the panel colors; a pin that disagrees derives a palette of the pinned polarity. The mode is read from the frame's actual background, so a theme that leaves `background-mode` stale is still read correctly.

**Semantics.** The result carries the ETAF UI token vocabulary this package paints with: `:ui-mode`, `:ui-bg`, `:ui-fg`, `:ui-panel-bg`, `:ui-panel-fg`, `:ui-muted-fg`, `:ui-panel-border`, `:ui-accent`, `:ui-accent-fg` and the button and panel tokens derived from them. A panel opened by `etaf-posframe-show` already provides it, so this function is for an application that builds its own boundary — a second child frame, a region of a panel — and wants the same palette. Ink on a filled accent follows the accent's luminance, so a dark theme with a pale accent and a light theme with a deep one both get readable labels.

**Returns.** A Theme plist.

**Example.**

```elisp
(let ((theme (etaf-posframe-theme nil 'dark)))
  (plist-get theme :ui-panel-bg))
```

#### Variable: etaf-posframe-border-width

Frame border width in pixels, 0 to 19, used when `:border` has no `:width`.

**Semantics.** A one-pixel border in the theme's border color is what separates a panel from the buffer behind it and makes it read as a floating surface. The panel's `:border` option overrides it per panel.

#### Variable: etaf-posframe-border-focus-strength

How much of the Theme accent a focused border shows, 0 to 1, default 0.6.

**Semantics.** The border is the panel surface tinted toward the theme's `link` color: 0 keeps the surface and 1 paints the accent itself. A per-panel `:border` `:focus` color replaces the tint entirely. Tinting instead of painting the accent keeps a one-pixel outline from reading as a saturated frame in either palette.

#### Variable: etaf-posframe-border-hover-strength

How much of the Theme accent a hovered border shows, 0 to 1, default 0.3.

**Semantics.** A hovered panel does not hold the keyboard, so it hints at the accent more weakly than a focused one. Keep it below `etaf-posframe-border-focus-strength` so hovering hints and clicking commits stay distinct; a per-panel `:border` `:hover` color replaces the tint.

## Sizes and fitting

<!-- index: panel width; panel height; panel fill height -->

#### Variable: etaf-posframe-default-width

Columns of a new panel when `:width` is absent, 56 by default.

**Semantics.** The value is a column count of content, not of the frame: the border, the padding and the title bar are added around it. A panel whose content is drawn on a fixed grid passes `:width` instead, and a panel that should fill a fraction of the frame passes `(fraction F)`.

**See also.** `etaf-posframe-show`, `etaf-posframe-default-max-height`.

#### Variable: etaf-posframe-default-max-height

Maximum content lines of a new panel when `:height` is absent, 30 by default.

**Semantics.** The panel fits its frame to the rendered content up to this budget, so a short View gets a short panel. A panel that must keep a fixed height, such as a game board on a fixed grid, passes `:fill-height` with `:height` and the surface paints the rest.

**See also.** `etaf-posframe-show`, `etaf-posframe-default-width`.

## Errors and recovery

<!-- index: etaf-posframe-error -->

#### Error: etaf-posframe-error

Signals invalid panel input and unavailable capabilities.

**Semantics.** The condition reports an unknown option, an invalid anchor, a non-positive size, a `:border` plist of the wrong shape, or a non-graphical frame. A failed show cleans up before it signals: the View is unmounted and the frame is deleted, so a caller that catches the error and retries with valid options starts from a clean state instead of leaking a frame.

| Failure | What happens |
| --- | --- |
| An option name is unknown | `etaf-posframe-error` before a frame is created |
| An anchor or size is invalid | `etaf-posframe-error`; nothing is left open |
| Emacs runs without a graphical frame | `etaf-posframe-error`; a panel needs child frames |

**See also.** `etaf-posframe-show`, [Standard Errors](standard-errors.md).
