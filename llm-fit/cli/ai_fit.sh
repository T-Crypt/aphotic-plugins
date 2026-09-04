#!/usr/bin/env bash
# `aphotic ai fit` -- hardware-aware model recommendations from llmfit.
#
# Sourced by core's plugin CLI dispatch (aphotic_plugin_cli_run), not
# executed, so aphotic_err/aphotic_warn/aphotic_log/aphotic_require and the
# XDG paths are already in scope exactly as they are for a core cmd_*.sh.
#
# Lived in core's cmd_ai.sh until the `cli` capability existed. The pane
# half of this plugin shipped first and the command could not follow, which
# is the gap that capability closes: the Hardware Advisor is one plugin
# again, UI and command together, and both leave with it.

aphotic_require jq || return 1

if ! command -v llmfit >/dev/null 2>&1; then
    aphotic_err "llmfit not found on PATH"
    aphotic_log "install it via the 'ai' profile layer (./install.sh --with ai), or manually: curl -fsSL https://llmfit.axjns.dev/install.sh | sh"
    return 1
fi

_llm_fit_limit="${1:-3}"
_llm_fit_out="$(mktemp)"
_llm_fit_err="$(mktemp)"
_llm_fit_rc=0

llmfit recommend --json --limit "$_llm_fit_limit" >"$_llm_fit_out" 2>"$_llm_fit_err" || _llm_fit_rc=$?

if [[ -s "$_llm_fit_err" ]]; then
    aphotic_warn "llmfit reported:"
    sed 's/^/  /' "$_llm_fit_err" >&2
fi

if [[ "$_llm_fit_rc" -ne 0 ]] || ! jq empty "$_llm_fit_out" >/dev/null 2>&1; then
    aphotic_err "llmfit failed to detect hardware or produce valid JSON (exit ${_llm_fit_rc})"
    rm -f "$_llm_fit_out" "$_llm_fit_err"
    return 1
fi

echo "Hardware detected:"
jq -r '.system |
    "  CPU:  \(.cpu_name) (\(.cpu_cores) cores)",
    "  RAM:  \(.available_ram_gb) / \(.total_ram_gb) GB available",
    (if .has_gpu then "  GPU:  \(.gpu_name) (\(.gpu_vram_gb) GB, \(.backend))" else "  GPU:  none detected" end)
' "$_llm_fit_out"
echo
echo "Top recommendations:"
if [[ "$(jq '.models | length' "$_llm_fit_out")" -eq 0 ]]; then
    echo "  (no models meet the minimum fit threshold on this hardware)"
else
    jq -r '.models | to_entries[] |
        "  \(.key + 1). \(.value.name) (\(.value.provider)) -- \(.value.fit_level) fit, \(.value.best_quant), ~\(.value.estimated_tps) tok/s",
        "     \(.value.parameter_count) params, \(.value.context_length) ctx, score \(.value.score)/100"
    ' "$_llm_fit_out"
fi

rm -f "$_llm_fit_out" "$_llm_fit_err"
