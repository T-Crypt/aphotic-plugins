#!/usr/bin/env bash
# skills/cli/skills.sh -- `aphotic skills`, the terminal half of the Skill
# Manager.
#
# Sourced by core's plugin dispatch (aphotic_plugin_cli_run) in a subshell,
# so aphotic_err/aphotic_log are normally in scope, and executed directly by
# qml/SkillsService.qml, where they are not. Every helper this script uses
# therefore has a plain-stdout fallback, and the whole body lives in main()
# so `return` works whether it is sourced or run.
#
# This file is a thin veneer over the skills-manager CLI. It resolves the
# binary through lib/skillscli.sh (the same file the QML service runs, so
# there is one resolution rule), forwards arguments unchanged to `raw`, and
# adds two things the CLI has no reason to know about: `doctor`, which
# gathers everything the pane needs in one JSON object, and `path`, which
# wraps the repository location subcommands.

set -uo pipefail

_sk_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_sk_plugin_dir="$(cd "${_sk_dir}/.." && pwd)"
# shellcheck source=../lib/skillscli.sh
source "${_sk_plugin_dir}/lib/skillscli.sh"

_sk_err() {
    if declare -F aphotic_err >/dev/null 2>&1; then aphotic_err "$@"; else printf '%s\n' "$*" >&2; fi
}
_sk_log() {
    if declare -F aphotic_log >/dev/null 2>&1; then aphotic_log "$@"; else printf '%s\n' "$*" >&2; fi
}
_sk_warn() {
    if declare -F aphotic_warn >/dev/null 2>&1; then aphotic_warn "$@"; else printf '%s\n' "$*" >&2; fi
}

# Align the tab-separated columns jq emits when `column` is available, and
# fall back to the raw tabs when it is not. Cosmetic only.
_sk_columns() {
    if command -v column >/dev/null 2>&1; then column -t -s $'\t'; else cat; fi
}

# The resolved binary, or a short explanation on stderr and status 1.
_sk_cli() {
    local path
    path="$(skillscli_resolve)" || {
        skillscli_install_hint >&2
        return 1
    }
    printf '%s\n' "$path"
}

_sk_require_cli() {
    _sk_cli >/dev/null
}

_sk_cmd_doctor() {
    local json="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json="true" ;;
            *) _sk_err "doctor: unknown option '$1'"; return 2 ;;
        esac
        shift
    done

    local cli="" source="" version="" pinned pinned_path
    pinned="$(skillscli_pin_version)"
    pinned_path="$(skillscli_pinned_path)"
    if cli="$(skillscli_resolve 2>/dev/null)"; then
        source="$(skillscli_resolve_source)"
        version="$(skillscli_version_of "$cli")"
    fi

    if [[ "$json" == "true" ]]; then
        command -v jq >/dev/null 2>&1 || { _sk_err "doctor --json needs jq"; return 1; }
        local repo agents skills presets matches
        if [[ -n "$cli" ]]; then
            repo="$("$cli" --json repo status 2>/dev/null || echo '{}')"
            agents="$("$cli" --json agents list 2>/dev/null || echo '[]')"
            skills="$("$cli" --json skills list 2>/dev/null || echo '[]')"
            presets="$("$cli" --json presets list 2>/dev/null || echo '[]')"
        else
            repo='{}'; agents='[]'; skills='[]'; presets='[]'
        fi
        [[ "$version" == "$pinned" ]] && matches=true || matches=false
        jq -n \
            --argjson ok "$([[ -n "$cli" ]] && echo true || echo false)" \
            --arg cli "$cli" --arg source "$source" --arg version "$version" \
            --arg pinned_version "$pinned" --arg pinned_path "$pinned_path" \
            --argjson version_matches "$matches" \
            --arg hint "$( [[ -n "$cli" ]] && echo "" || skillscli_install_hint )" \
            --argjson repo "$repo" --argjson agents "$agents" \
            --argjson skills "$skills" --argjson presets "$presets" \
            '{ok: $ok, cli: {path: $cli, source: $source, version: $version,
              pinned_version: $pinned_version, pinned_path: $pinned_path,
              version_matches: $version_matches}, hint: $hint,
              repo: $repo, agents: $agents, skills: $skills, presets: $presets}'
        return 0
    fi

    if [[ -z "$cli" ]]; then
        skillscli_install_hint
        return 1
    fi
    printf 'cli        %s\n' "$cli"
    printf 'source     %s\n' "$source"
    if [[ "$version" == "$pinned" ]]; then
        printf 'version    %s (the pinned build)\n' "$version"
    else
        printf 'version    %s (pin is %s; updating is a CLI concern, not this plugin'"'"'s)\n' "$version" "$pinned"
    fi
    if [[ "$source" == "path" && "$version" != "$pinned" ]]; then
        _sk_warn "the binary on PATH is not the pinned build; the JSON contract is not guaranteed"
    fi
    local repo
    repo="$("$cli" --json repo status 2>/dev/null || echo '{}')"
    if command -v jq >/dev/null 2>&1; then
        printf 'library    %s\n' "$(jq -r '.base_dir // "unknown"' <<<"$repo")"
        printf 'skills     %s\n' "$(jq -r '.skill_count // 0' <<<"$repo")"
        printf 'presets    %s\n' "$(jq -r '.preset_count // 0' <<<"$repo")"
    fi
    return 0
}

# The library location. `status` only reads; the two writers change where
# every agent's skills come from, so they are named as what they are.
_sk_cmd_path() {
    local cli
    cli="$(_sk_cli)" || return 1
    case "${1:-}" in
        "") exec "$cli" --json repo status ;;
        --set)
            [[ -n "${2:-}" ]] || { _sk_err "path --set needs a directory"; return 2; }
            exec "$cli" --json repo set-path "$2" ;;
        --reset)
            exec "$cli" --json repo reset-path ;;
        *)
            _sk_err "path: expected nothing, --set DIR, or --reset"
            return 2
            ;;
    esac
}

_sk_cmd_list() {
    local cli
    cli="$(_sk_cli)" || return 1
    if [[ "${1:-}" == "--json" ]]; then
        exec "$cli" --json skills list
    fi
    local rows
    rows="$("$cli" --json skills list)" || return 1
    if ! command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$rows"
        return 0
    fi
    if [[ "$(jq 'length' <<<"$rows")" == "0" ]]; then
        _sk_log "The library is empty. Add a skill, then deploy it to an agent."
        return 0
    fi
    {
        printf 'NAME\tAGENTS\tTAGS\tSOURCE\n'
        jq -r '.[] | [.name, (.deployed_to|length|tostring), (.tags|join(",")),
                (.source_type + (if .source_ref then " " + .source_ref else "" end))] | @tsv' <<<"$rows"
    } | _sk_columns
}

# `deploy`/`undeploy` take the skill first and then any number of agents,
# which is the order the pane's buttons produce. The CLI itself wants one
# repeated --agent flag, so it is built here rather than in the caller.
_sk_cmd_pair() {
    local action="$1"; shift
    local cli
    cli="$(_sk_cli)" || return 1
    local skill="${1:-}"; shift || true
    if [[ -z "$skill" ]]; then
        _sk_err "$action: name a skill (see 'aphotic skills list')"
        return 2
    fi
    local args=(--json skills "$action" "$skill")
    local agent
    for agent in "$@"; do
        args+=(--agent "$agent")
    done
    exec "$cli" "${args[@]}"
}

_sk_cmd_agents() {
    local cli; cli="$(_sk_cli)" || return 1
    if [[ "${1:-}" == "--json" ]]; then exec "$cli" --json agents list; fi
    local rows; rows="$("$cli" --json agents list)" || return 1
    if ! command -v jq >/dev/null 2>&1; then printf '%s\n' "$rows"; return 0; fi
    {
        printf 'KEY\tAGENT\tINSTALLED\tENABLED\tSKILLS DIR\n'
        jq -r '.[] | [.key, .display_name, (.installed|tostring), (.enabled|tostring), .skills_dir] | @tsv' <<<"$rows"
    } | _sk_columns
}

_sk_cmd_presets() {
    local cli; cli="$(_sk_cli)" || return 1
    if [[ "${1:-}" == "--json" ]]; then exec "$cli" --json presets list; fi
    local rows; rows="$("$cli" --json presets list)" || return 1
    if ! command -v jq >/dev/null 2>&1; then printf '%s\n' "$rows"; return 0; fi
    {
        printf 'ACTIVE\tNAME\tSKILLS\tDESCRIPTION\n'
        jq -r '.[] | [(if .active then "*" else "" end), .name, (.skill_count|tostring), (.description // "")] | @tsv' <<<"$rows"
    } | _sk_columns
}

_sk_usage() {
    cat <<'EOF'
aphotic skills -- the shared agent-skill library

  list [--json]                 every skill, and how many agents have it
  show <skill> [--json]         one skill, including its SKILL.md text
  deploy <skill> <agent>...     publish a skill to one or more agents
  undeploy <skill> <agent>...   take it back off those agents
  status <skill> [--json]       per-agent state for one skill
  agents [--json]               the agents the CLI knows about
  presets [--json]              the presets and what is in them
  adopt [--json]                import skills found in agent directories
  check <skill>|--all           report skills whose source moved on
  path [--set DIR|--reset]      where the library lives
  doctor [--json]               binary, version, library and counts
  raw <args...>                 pass everything straight to the CLI
  help

The library is ~/.skills-manager by default, the same directory the upstream
desktop app uses, so both see one set of skills.
EOF
}

main() {
    local cmd="${1:-list}"
    shift || true
    case "$cmd" in
        list)              _sk_cmd_list "$@" ;;
        show)
            local cli; cli="$(_sk_cli)" || return 1
            [[ -n "${1:-}" ]] || { _sk_err "show: name a skill"; return 2; }
            if [[ "${2:-}" == "--json" ]]; then exec "$cli" --json skills show "$1"; fi
            exec "$cli" skills show "$1" ;;
        deploy)            _sk_cmd_pair deploy "$@" ;;
        undeploy|disable)  _sk_cmd_pair undeploy "$@" ;;
        status)
            local cli; cli="$(_sk_cli)" || return 1
            [[ -n "${1:-}" ]] || { _sk_err "status: name a skill"; return 2; }
            if [[ "${2:-}" == "--json" ]]; then exec "$cli" --json skills status "$1"; fi
            exec "$cli" skills status "$1" ;;
        agents)            _sk_cmd_agents "$@" ;;
        presets)           _sk_cmd_presets "$@" ;;
        adopt)
            local cli; cli="$(_sk_cli)" || return 1
            if [[ "${1:-}" == "--json" ]]; then exec "$cli" --json skills adopt; fi
            exec "$cli" skills adopt ;;
        check)
            local cli; cli="$(_sk_cli)" || return 1
            if [[ "${1:-}" == "--all" || "${1:-}" == "--json" ]]; then
                exec "$cli" --json skills check --all
            elif [[ -n "${1:-}" ]]; then
                exec "$cli" --json skills check "$1"
            else
                _sk_err "check: name a skill or pass --all"
                return 2
            fi ;;
        path|library)      _sk_cmd_path "$@" ;;
        doctor)            _sk_cmd_doctor "$@" ;;
        raw)
            local cli; cli="$(_sk_cli)" || return 1
            exec "$cli" "$@" ;;
        resolve|where)
            skillscli_resolve ;;
        help|--help|-h)    _sk_usage ;;
        *)
            _sk_err "skills: unknown subcommand '$cmd'"
            _sk_usage
            return 2 ;;
    esac
}

main "$@"
