# Captured fixtures

Every JSON file here was captured from the real `skills-manager-cli` 1.42.0
(the Linux x64 release asset this plugin pins) so the plugin's tests can run
with no binary and no network. They are evidence of the wire shape, not
hand-written samples.

| File | Captured from |
|---|---|
| `repo-status.json` | `skills-manager-cli --json repo status` |
| `agents.json` | `skills-manager-cli --json agents list` |
| `skills.json` | `skills-manager-cli --json skills list` |
| `presets.json` | `skills-manager-cli --json presets list` |
| `show.json` | `skills-manager-cli --json skills show demo-skill` |
| `status.json` | `skills-manager-cli --json skills status demo-skill` |
| `conflict.json` | `skills-manager-cli skills deploy conflict-demo --agent claude_code`, declined with `TARGET_CONFLICT` on stderr and exit 1 |
| `doctor.json` | `skills.sh doctor --json`, the wrapper's own aggregate, which is what the QML service parses |

The capture machine kept its library under a throwaway home. Those paths are
rewritten here to `/home/user`, which is inert. `tests/fixtures/skills-manager-cli`
rewrites that prefix to `$HOME` at read time, so a test asserts on the library
it actually created rather than on one it never had.

Recapture after bumping the pin in `lib/skillscli.sh`: download the asset,
point `APHOTIC_SKILLS_CLI` at it with `HOME` set to a scratch directory, run each
command above, and keep the output verbatim apart from the path rewrite.
`tests/test_contract.sh` compares the live `doctor --json` keys against
`doctor.json` and the live `list` and `status` keys against their fixtures, so a
capture that drops a key fails the suite rather than silently shrinking what
the pane can read.
