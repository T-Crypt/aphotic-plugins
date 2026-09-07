# Dev Ports

Claims a Workspace tab and lists whatever on this machine is currently
answering HTTP on a loopback port -- start a dev server, a local tool's
GUI, a model server, anything that binds a port and speaks HTTP, and it
shows up here with a click-to-open link. No per-app integration: it
scans instead of asking anything to register itself.

## What it does

- `bin/scan.sh` runs `ss -tlnp` to find every TCP socket listening on
  `127.0.0.1`/`0.0.0.0`/`::1`/`::` (this machine's own reach), then
  probes each port with a short `curl` request. A port that answers HTTP
  is real HTTP; a port that doesn't (databases, `sshd`, DNS) is filtered
  out entirely, not shown greyed out.
- Results merge into `~/.config/aphotic/plugins/dev-ports/services.json`,
  keyed by port. A port that answered on a previous scan but not this
  one is kept and marked offline (dimmed, no open action) instead of
  dropped, so a service you just aren't running right now still shows
  its last-known address. "Clear offline" drops everything currently
  marked offline.
- Process name comes from `ss -p`, which only resolves for sockets your
  own user owns and can see. A service run as another user, or through a
  wrapper that hands the socket off, shows as "unknown" with the port
  still correct -- the address is what matters for opening it.

## Cost at idle

Nothing. The Workspace pane's own Loader only creates this component
while its tab is open and selected; leaving the tab destroys it, which
stops its 4-second scan timer for free. While open: one `ss` call and
one short (0.6s max) `curl` probe per currently-listening loopback port,
every 4 seconds.

## What this deliberately doesn't do

Opens the service in your default browser (`xdg-open`), not inside the
pane. Embedding an actual page render in-shell would need `QtWebEngine`
(Chromium), a real new dependency this project doesn't carry anywhere
today -- a call worth making deliberately if it's ever wanted, not as a
side effect of a ports list.
