# Gaming Profile

Registers the `gaming` profile with Aphotic's Profile Engine and runs the
full DETECT → LOAD → NEGOTIATE → APPLY → MONITOR → EXIT → RESTORE
lifecycle around a running game. It draws nothing: the shell loads it
headlessly, the same way it loads a UI-surface plugin's QML, and the
profile's state shows up wherever profile state already does.

What it actually does, and deliberately nothing more:

- **Detects games through gamemode.** It subscribes to gamemoded's own
  `GameRegistered`/`GameUnregistered` session-bus signals with a bare
  match rule — an event stream, not a poll, with no timer running between
  games. A game already registered when the shell starts is caught by a
  one-shot `ListGames` call, itself guarded on gamemoded already running
  so that merely watching never auto-activates the daemon.
- **Engages do-not-disturb while you play**, and releases it on RESTORE.
  DND is borrowed, not owned: if you had it on yourself, or Pomodoro is
  holding it, a game ending will not clear it.
- **Claims the game's VRAM at foreground priority**, through the Resource
  Engine's PID-adoption seam. This is the half that makes the AI ↔ Gaming
  negotiation real — a local model holding GPU memory in the background is
  the side asked to yield, and the game is never the side asked to stop.

No performance tuning. gamemode already owns the CPU governor and GPU
clock state the moment a game registers, so duplicating it here would just
be a second, worse copy. Nothing here ever stops gamemoded either — if
this plugin did not start it, it is not this plugin's to tear down.

## Requirements

- The `gaming` layer installed (`requires_layer = "gaming"`), which is
  what puts `gamemode` on the machine. Without it this component is not
  loaded at all — it is not loaded-and-idle, it is absent, and the
  `gaming` profile simply does not exist.
- Games launched under gamemode (`gamemoderun`, Steam's launch options,
  or a user-enabled `gamemoded.service`). A game started outside gamemode
  registers nothing, so there is nothing for this to detect.
- `dbus-monitor` and `gdbus`, from `dbus` and `glib2` — both already
  installed by every Aphotic base profile, so they are not redeclared as
  plugin dependencies here.

The GPU VRAM claim additionally needs a GPU whose per-process memory the
Resource Engine can read (NVIDIA today). Without one, detection, DND and
the lifecycle all still work; only the claim is absent.

## Install

```sh
aphotic plugin install gaming
```

## Removing it removes gaming detection

This is the whole of Aphotic's gaming-domain behaviour, not an add-on to
it. Removing or disabling this plugin removes game detection, the DND
engagement and the VRAM claim entirely — the `gaming` layer on its own no
longer provides any of them. The layer installs the gaming *packages*;
this plugin is what makes the desktop react to them.

Removal is clean: the component's teardown deactivates the profile,
restores DND and releases every claim it adopted before it goes.
