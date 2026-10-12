# Buttons and Choice Controls

The catalog's action and selection controls all follow one controlled contract: a value prop plus a change callback, or a writable ref through `:bind`, with the application owning the value and the component only rendering it and reporting what the user did. Buttons commit an action, checkbox and switch own a boolean, radio and segmented pick from a fixed list, and slider and range report a number that the caller stores. This chapter defines the seven controls, their keyboard behavior and their shared color tokens. [UI Overview](ui-overview.md) defines the controlled contract, [Events](events.md) how a press reaches a callback, [Focus](focus.md) and [Keyboard](keyboard.md) the Tab and arrow behavior the controls inherit, and [Component Styles and Themes](component-styles-and-themes.md) the token mechanism.

## The shared selection contract

<!-- index: controlled control; tonal pill; selection state; bind -->

Selection controls are *tonal pills* rather than boxed fields: a selected control paints the secondary button tint, an unselected one inherits its surface, and none carries an outline. Because the secondary tints are dialog tokens, a selected control stays crisp inside a modal above a dimmed shell. Geometry never changes with selection — state is paint, not layout — so switching a segment or checking a box never moves a neighbour.

Each control reads its input through the same contract. An explicit `:value` or `:checked` prop and an `:on-change` callback form the controlled pair; a writable ref passed as `:bind` replaces both, and its current value supplies the displayed state. A non-nil bind together with an explicit value or callback is rejected, and the conflict names the offending property. The ref belongs to the caller: a rejected publication keeps the previous binding target, and unmounting releases the control's handlers and subscriptions without touching the ref.

`DISABLED` removes the control's callback and its Tab stop while keeping its footprint, so toggling availability never shifts the layout. An additive `:on-press` observer may be supplied alongside the controlled interface; it observes activation without becoming the value path.

## The button

<!-- index: etaf-button; button variant; failed publication; ghost -->

#### Component: etaf-button (&key label on-press disabled id ref class color bgcolor border padding font-size font-weight tab-index aria-label help-echo hover-content hover-group pointer use variant)

Render a standard pressable Button with a committed callback.

**Arguments.** LABEL names the button and is shown unless a default slot replaces it. ON-PRESS is the zero-argument callback. DISABLED removes the callback and the default Tab index. VARIANT is `primary` (accent fill, bold; the default), `secondary` (soft accent tint) or `ghost` (inherits its surface, narrower padding); every variant is a borderless single-row pill whose second class name carries the variant. The presentation props COLOR, BGCOLOR, BORDER, PADDING, FONT-SIZE and FONT-WEIGHT override the variant's defaults. ID reaches the rendered Host so anchor-based surfaces can reference the Button by identity; CLASS, REF, TAB-INDEX, ARIA-LABEL, HELP-ECHO, HOVER-CONTENT, HOVER-GROUP, POINTER and USE are the ordinary Host capabilities.

**Semantics.** The Runtime publishes ON-PRESS together with the visible Button, so a render that fails to publish keeps the previous callback and the values it captured. A Button is one row: it never shrinks below its label or wraps the label's text, so a Flex line that runs out of room moves the whole Button instead of splitting its text.  A default slot replaces the visible label with ordinary non-interactive content, such as a title and description; LABEL or ARIA-LABEL still names the single focus and activation target, and nested controls inside a button are inappropriate. The native root attributes `:pointer`, `:help-echo`, `:hover-style` and `:hover-content` request Ebox's text-property capabilities, and an explicit nil blocks an inherited capability.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when a name is neither a declared prop nor a supported Host attribute.

**Example.**

```elisp
(etaf-button :label "Save" :variant 'primary :on-press #'save-buffer)
```

**See also.** `etaf-checkbox`, `:ui-button-primary-bg`.

## Checkbox and switch

<!-- index: etaf-checkbox; etaf-switch; checkbox mark; switch state -->

#### Component: etaf-checkbox (&key checked label on-change disabled bind)

Render a controlled Checkbox whose next value is sent to ON-CHANGE.

**Arguments.** CHECKED is the displayed boolean, a ref or a computed. ON-CHANGE receives the next boolean. LABEL is the visible caption and the accessible name. BIND is an existing writable ref that replaces CHECKED and ON-CHANGE.

**Semantics.** The control draws a bold `[x]` or `[ ]` mark followed by the label. No additional state is created: an external write to a bound ref updates the control, a disabled control cannot write, and an additive `:on-press` observer sees activation without affecting the value path. Failed publication retains the old binding target, and unmounting releases the control's handlers and subscriptions without owning the caller's ref.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when a non-nil BIND is combined with an explicit CHECKED or ON-CHANGE (including nil), naming the conflicting property, or when BIND is not a writable ref.

**Example.**

```elisp
(etaf-checkbox :label "Auto-save" :checked t)
```

**See also.** `etaf-switch`, `:ui-checkbox-enabled-fg`.

#### Component: etaf-switch (&key checked label on-change disabled bind)

Render a controlled binary switch with Checkbox's ownership contract.

**Arguments.** CHECKED must be a boolean, ref or computed; LABEL defaults to `"Switch"`; BIND follows `etaf-checkbox`.

**Semantics.** The switch is a single ghost button whose caption is `"[x] LABEL"` or `"[ ] LABEL"`, painted with the selection tint when on. Its accessible name is LABEL.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when CHECKED is not boolean-valued after resolution or LABEL is not a string.

**Example.** `(etaf-switch :checked nil :label "Aeroplane mode")`

## Radio and segmented

<!-- index: etaf-radio; etaf-segmented; option alist; tab list -->

#### Component: etaf-radio (&key value options label on-change disabled bind)

Render a controlled single-choice group from an options alist.

**Arguments.** OPTIONS is a nonempty alist of unique scalar values to unique nonempty string labels. VALUE is nil or one of the option values. LABEL names the group and defaults to `"Choice"`. ON-CHANGE receives the chosen value; BIND follows `etaf-checkbox`.

**Semantics.** The group is a labelled column whose options share one horizontal focus group, so the arrows move between choices. Each choice is a ghost button whose caption is prefixed `"(o) "` when selected and `"( ) "` when not, and the selected one paints the selection tint. The group's role is `radiogroup` and each choice carries its label as its accessible name.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` for an empty or malformed OPTIONS, for duplicate values or labels, for a VALUE outside OPTIONS, or for a non-string LABEL.

**Example.**

```elisp
(etaf-radio :value 'b :label "Mode"
            :options '((a . "Alpha") (b . "Beta")))
```

**See also.** `etaf-segmented`, `:ui-button-secondary-bg`.

#### Component: etaf-segmented (&key value options on-change disabled bind)

Render a compact mutually-exclusive selector from an options alist.

**Arguments.** OPTIONS, VALUE, ON-CHANGE and BIND follow `etaf-radio`; there is no caption label.

**Semantics.** The segments are buttons in one horizontal focus group with a two-column gap and the `tablist` role. Selection is carried purely by the button variant — the selected segment uses the secondary variant and the others are ghosts — so no prefix changes the caption width and the row never jumps when the selection moves.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` for an empty or malformed OPTIONS, for duplicate values or labels, or for a VALUE outside OPTIONS.

**Example.**

```elisp
(etaf-segmented :value 'day
                :options '((day . "Day") (week . "Week") (month . "Month")))
```

## Slider

<!-- index: etaf-slider; integer slider; native prompt; step alignment -->

#### Component: etaf-slider (&key value min max step label on-change disabled bind)

Render a controlled numeric slider.

**Arguments.** VALUE must be an integer between MIN and MAX aligned to STEP. MIN and MAX are integers with `min <= max` (defaults 0 and 100); STEP is a positive integer (default 1). LABEL defaults to `"Value"`. ON-CHANGE receives the next integer; BIND follows `etaf-checkbox`.

**Semantics.** The slider is a labelled column: a strong caption and a muted current value, then a secondary button reading `"◀  N  ▶"`. With the button focused, Left and Right report VALUE moved by one STEP through the direction channel and Home and End are not bound; the native number prompt is reachable by activating the button, which opens `read-number` outside the layout, restores focus afterwards, and writes the result only after it passes the same integer, range and STEP-alignment checks. Cancelling the prompt leaves the value unchanged.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when MIN or MAX is not an integer, MAX is below MIN, STEP is not a positive integer, LABEL is not a string, or VALUE is not an aligned integer within the bounds. The native prompt reports a misaligned or out-of-range entry as a `user-error` and does not write it.

**Example.**

```elisp
(etaf-slider :value 4 :min 0 :max 10 :step 2 :label "Level")
```

## Range

<!-- index: etaf-range; retained fill; drag preview; commit callback; reactive bounds -->

#### Component: etaf-range (&key value min max step key-step on-change on-commit disabled color track-color bar-height label ref fill-ref)

Render a controlled interactive Range (progress, seek, volume) within MIN..MAX.

**Arguments.** VALUE is a number or reactive source within MIN..MAX, snapped to STEP when STEP is non-nil. MIN and MAX accept numbers or reactive sources. KEY-STEP is the arrow step and defaults to STEP, else a twentieth of the span. ON-CHANGE reports intermediate values and ON-COMMIT the released one. BAR-HEIGHT is the painted thickness as a percentage of the row (default 40). COLOR and TRACK-COLOR override the fill and track tokens. LABEL is the accessible name. REF names the track Host and FILL-REF the fill Host.

**Semantics.** The bar is a track in normal flow carrying a rule string, with the accent fill painted above it as an absolutely positioned Host whose width is a percentage. A pointer click reports the pointed value through ON-CHANGE and ON-COMMIT; dragging reports intermediate values through ON-CHANGE and the released value through ON-COMMIT. A press or drag re-proportions the two parts through retained Host geometry before the caller's value arrives, so the gesture follows the pointer while a backend reply is pending. With the range focused, Left and Right report the value moved by KEY-STEP and Home and End report MIN and MAX. A caller may move the fill in place with `etaf-runtime-update-host-geometries` and a `:width` percentage without republishing the View, which is how a playing position advances. Bounds that change through a reactive source are read at the retained fill, and a pending nil bound paints an empty span instead of failing.

**Returns.** A View.

**Errors.** `error→ etaf-component-call-error` when MIN or MAX is neither a number nor a reactive source, a static MAX is below MIN, STEP or KEY-STEP is not a positive number, BAR-HEIGHT is not an integer percentage from 1 through 100, ON-CHANGE or ON-COMMIT is neither a function nor nil, or DISABLED is not a boolean. A resolved reactive MAX below MIN signals when the retained fill reads it.

**Example.**

```elisp
(etaf-range :value 30 :min 0 :max 100 :on-change #'preview-volume
            :on-commit #'set-volume :label "Volume")
```

**See also.** `:ui-range-fill`, `:ui-range-track`, [Dragging and Gestures](dragging-and-gestures.md).

## Choice tokens

<!-- index: ui-button-primary-fg; ui-button-secondary-fg; ui-checkbox-enabled-fg; ui-range-fill -->

#### Token: :ui-button-primary-fg

The foreground of a primary button.

**Semantics.** Painted on `:ui-button-primary-bg` for the filled accent button, which uses bold text.

#### Token: :ui-button-primary-bg

The fill of a primary button.

#### Token: :ui-button-secondary-fg

The foreground of a secondary button and of a selected choice.

**Semantics.** Checkbox marks, radio and segmented selections, switch-on labels and picker rows paint this color on `:ui-button-secondary-bg`; because they are dialog tokens, a selected control stays crisp above a dimmed shell.

#### Token: :ui-button-secondary-bg

The tint of a secondary button and of a selected choice.

#### Token: :ui-button-ghost-fg

The foreground of a ghost button.

**Semantics.** A ghost button inherits its surface and paints only its text, which is why an unselected segment or a plain tag close control reads as content rather than as a box.

#### Token: :ui-checkbox-enabled-fg

The label color of an enabled checkbox.

#### Token: :ui-checkbox-disabled-fg

The label color of a disabled checkbox.

#### Token: :ui-range-fill

The accent fill of a range bar.

**Semantics.** Painted above the track for the filled part of the value; a caller may override it per instance with the range's `:color` prop.

#### Token: :ui-range-track

The unfilled track of a range bar.

**Semantics.** Drawn as the rule string the pointer hits, so its measured width is what maps a pointer position to a value; a caller may override it with `:track-color`.

## Errors and recovery

- `error→ etaf-component-call-error` reports every rejected input through `etaf-check-prop`, naming the component, the property, the received value and the expectation: a bind combined with an explicit value or callback, a malformed or duplicate option list, a value outside the options, a non-integer slider bound or a misaligned slider value, and the range's bound, step, thickness and callback contracts.
- A failed publication keeps the last committed state: a button keeps its previous callback and captured values, and a bound control keeps its previous binding target. The caller's business ref is never rolled back by the component.
- A disabled control is not inert markup: it removes its callback and Tab stop, so activation cannot reach it while its layout footprint stays.
- The slider's native prompt is the one place the control leaves the layout: a cancelled prompt changes nothing, and a misaligned entry is reported as a `user-error` without a write.

**See also.** [UI Overview](ui-overview.md#errors-and-recovery).

```elisp :run
(etaf-view
 (column :item-gap '(lh 1)
   (row :item-gap '(ch 1)
     (etaf-button :label "Save" :on-press #'ignore)
     (etaf-button :label "Cancel" :variant 'ghost :on-press #'ignore))
   (etaf-segmented :value 'week
                   :options '((day . "Day") (week . "Week")))
   (etaf-checkbox :label "Auto-save" :checked t)))
```
