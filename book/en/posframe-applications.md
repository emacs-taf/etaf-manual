# Panel Applications

A panel application is an ETAF application whose window is a floating panel: the timer, the player, the reader. Registering one describes how to create its session and how to render it, and the registry then opens, closes, keeps alive and binds a key for it, so an application does not write its own command, its own toggle or its own keymap. The panel surface itself is documented in [Floating Panels](posframe-panels.md); this chapter documents the registry.

## Registering an application

<!-- index: panel application; etaf-posframe-register-app; keep-alive; on-stop -->

#### Function: etaf-posframe-register-app (id &rest options)

Register an ETAF application as a floating panel.

**Arguments.** ID is a symbol naming the application. OPTIONS is a plist: `:title` is the human name and the panel's title-bar text; `:shortcut` is the key string `etaf-posframe-app-prefix` binds to this application; `:create` is a function returning a fresh session; `:view` is a function taking that session and returning its View; `:require` is a feature to load before creating a session; `:keep-alive` is t to hide the panel on close and keep the session for the next open, so music or a game continues, or nil to stop the application when its panel closes; `:on-stop` is a function called with the session when the application stops; and `:width`, `:height`, `:at`, `:stack`, `:focusable`, `:focus-on-open`, `:auto-hide`, `:theme`, `:border` and `:draggable` mean what they mean in `etaf-posframe-show`, with a top-right anchor, stacking, the default size and focus on open as the registration defaults.

**Semantics.** Registration is global and independent of any open panel: it records how to build the application and nothing else, so registering twice with the same ID replaces the record and its shortcut instead of opening two panels. The session is created by `:create` and owned by the panel; hiding a panel whose application is not `:keep-alive` stops it, so a closed panel leaves nothing running, and a `:keep-alive` application keeps its session until `etaf-posframe-app-quit` stops it. `:on-stop` is the one place an application releases what its session holds — a socket, a timer, a file.

**Returns.** The registered ID.

**Errors.** `etaf-posframe-error` for an ID that is not a symbol, a missing `:create` or `:view`, or an option that is not a function where one is required.

**Example.**

```elisp
(etaf-posframe-register-app
 'timer :title "Timer" :shortcut "t"
 :create #'my-timer-create :view #'my-timer-view
 :require 'my-timer
 :width 42 :at 'frame-top-right :stack t
 :focusable t :draggable t)
```

## Opening and closing

<!-- index: etaf-posframe-app; etaf-posframe-app-quit; application toggle -->

#### Function: etaf-posframe-app (id)

Open ID's panel, or close it when it is already open.

**Semantics.** Interactively with no ID it prompts among the registered applications. Opening mounts the whole application, so a repeated call within `etaf-posframe-app-repeat-delay` seconds is ignored; that guard matters because holding a key would otherwise mount the application once per repeat and stall Emacs. Closing a panel of an application without `:keep-alive` stops it, and opening it again creates a fresh session.

**Returns.** The panel when it opened, nil when it closed one.

**See also.** `etaf-posframe-app-quit`, `etaf-posframe-app-repeat-delay`.

#### Function: etaf-posframe-app-quit (id)

Stop application ID.

**Semantics.** It hides the panel, calls the application's `:on-stop` with the session and drops the session, so a `:keep-alive` application really exits. This is the difference between closing a window and quitting: closing hides, quitting releases. It is safe on an application that is not open.

**Returns.** Non-nil when an application was stopped.

**See also.** `etaf-posframe-register-app`, `etaf-posframe-app`.

#### Variable: etaf-posframe-app-repeat-delay

Seconds during which a repeated app toggle is ignored, 0.3 by default.

**Semantics.** Opening a panel mounts a whole application, so key repeat would otherwise mount it once per repeat and stall Emacs. Raising the value makes a held key slower to toggle twice; lowering it makes a deliberate double press toggle again sooner.

## Shortcuts and cycling

<!-- index: panel shortcut; etaf-posframe-app-prefix; etaf-posframe-cycle; etaf-posframe-app-map -->

A registration's `:shortcut` is a key string, and one binding opens all of them: `etaf-posframe-app-prefix` reads one key and opens the registered application bound to it, so every registration's shortcut works without the caller rebuilding a keymap. A caller that prefers to bind a keymap directly binds `etaf-posframe-app-map`, which carries one binding per registered shortcut.

#### Function: etaf-posframe-app-prefix ()

Read one key and open the registered application bound to it.

**Semantics.** Bind this once, then every registration's `:shortcut` works. It uses the same repeat guard as `etaf-posframe-app`, so holding the prefix key does not mount applications in a row.

**Returns.** The panel when it opened, nil otherwise.

**See also.** `etaf-posframe-app-map`, `etaf-posframe-app`.

#### Function: etaf-posframe-cycle ()

Move input focus to the next open panel, and from the last one back to the frame it belongs to.

**Semantics.** With no panel focused this focuses the most recent panel. It walks only panels that accept the keyboard, so cycling never lands on a panel the user cannot type into. Binding it to a key gives a keyboard route between the open applications and the buffer behind them.

**Returns.** The panel that received focus, or nil when focus returned to the buffer's own frame.

**See also.** `etaf-posframe-panels`, `etaf-posframe-panel-keys`.

#### Variable: etaf-posframe-app-map

Keymap with one binding per registered shortcut.

**Semantics.** The map is filled as applications are registered, so a caller binds the map once rather than one key per application. It is the direct form of `etaf-posframe-app-prefix`: the same shortcuts, reachable as a prefix map.

**See also.** `etaf-posframe-app-prefix`, `etaf-posframe-apps`.

#### Variable: etaf-posframe-apps

Registered applications as `(ID . PLIST)` records, in registration order.

**Semantics.** The records are what `etaf-posframe-app` reads to mount an application; a launcher that lists applications reads the same list instead of keeping its own copy. Registering again replaces the record in place.

**See also.** `etaf-posframe-register-app`, `etaf-posframe-app-map`.

## A complete registration

<!-- index: panel application example -->

The three parts of an application — create a session, render it, register it — fit in one place, and the panel keys, the shortcut and the quit path all come from the registry:

```elisp
(defun my-clock-create ()
  "Return a fresh session for the clock."
  (list :now (etaf-ref (current-time)) :timer (run-at-time 1 1 #'my-clock-tick)))

(defun my-clock-view (session)
  "Return SESSION's View."
  (etaf-view (text (format-time-string "%H:%M" (etaf-value (plist-get session :now))))))

(etaf-posframe-register-app
 'clock :title "Clock" :shortcut "c"
 :create #'my-clock-create :view #'my-clock-view
 :require 'my-clock
 :keep-alive t :on-stop (lambda (session) (cancel-timer (plist-get session :timer)))
 :theme 'dark :draggable t)

(global-set-key (kbd "C-c e") #'etaf-posframe-app-prefix)
```
