# security-notch-tile

Adds a Security notch tile showing posture (Shielded/Exposed/Engaged), exposure from network listeners, VPN state, firewall readability, SSH sessions, advisories and engagement control.

The tile polls `ss` every 5s only while visible and checks `arch-audit` at most once per 30 minutes while open. It never changes system state except VPN toggles and starting/ending an engagement.

## Requirements
- Security layer installed (`requires_layer = "security"`)
- `ss` must be available

Optional tools (`nft`, `arch-audit`) are detected at runtime.

## Install
```sh
aphotic plugin install security-notch-tile
```
