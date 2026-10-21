#!/usr/bin/env bash
# ==============================================================================
# Script Name: RHEL Modular CIS Benchmark Framework
# Author:      William Collison
# Architecture: RHEL 8 / 9 / 10
# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROLS_DIR="${SCRIPT_DIR}/controls"

# Privilege check
if [[ $EUID -ne 0 ]]; then
   echo "[!] This script must be executed as root (sudo)." >&2
   exit 1
fi

# Ensure whiptail is available
if ! command -v whiptail &>/dev/null; then
    dnf install -y newt || { echo "[!] Failed to install newt/whiptail. Exiting."; exit 1; }
fi

if [[ ! -d "$CONTROLS_DIR" ]]; then
    mkdir -p "$CONTROLS_DIR"
fi

# ------------------------------------------------------------------------------
# Recursive Module Discovery
# ------------------------------------------------------------------------------

declare -A MODULE_MAP
declare -A MODULE_NAMES
declare -A MODULE_SECTIONS
DISCOVERED_KEYS=()

load_modules() {
    MODULE_MAP=()
    MODULE_NAMES=()
    MODULE_SECTIONS=()
    DISCOVERED_KEYS=()

    # Discover all .sh files under controls/ subdirectories sorted naturally
    while IFS= read -r script; do
        [[ -f "$script" ]] || continue

        local sec_dir
        sec_dir="$(basename "$(dirname "$script")")"

        # Safely evaluate metadata in a subshell
        local id desc
        id=$(bash -c "source '$script' 2>/dev/null && echo \"\$CONTROL_ID\"")
        desc=$(bash -c "source '$script' 2>/dev/null && echo \"\$CONTROL_DESC\"")

        if [[ -n "$id" && -n "$desc" ]]; then
            MODULE_MAP["$id"]="$script"
            MODULE_NAMES["$id"]="$desc"
            MODULE_SECTIONS["$id"]="$sec_dir"
            DISCOVERED_KEYS+=("$id")
        fi
    done < <(find "$CONTROLS_DIR" -type f -name "*.sh" | sort -V)
}

# ------------------------------------------------------------------------------
# Engine Execution Loop
# ------------------------------------------------------------------------------

run_engine() {
    local mode="$1"
    local scope="$2"
    local -a targets=()

    load_modules

    if [[ ${#DISCOVERED_KEYS[@]} -eq 0 ]]; then
        whiptail --title "Notice" --msgbox "No controls found in ${CONTROLS_DIR}/*/" 8 50
        return
    fi

    if [[ "$scope" == "all" ]]; then
        targets=("${DISCOVERED_KEYS[@]}")
    else
        local checklist_args=()
        for key in "${DISCOVERED_KEYS[@]}"; do
            local sec="${MODULE_SECTIONS[$key]}"
            local desc="${MODULE_NAMES[$key]}"
            checklist_args+=("$key" "[Sec $sec] $desc" "OFF")
        done

        local choices
        choices=$(whiptail --title "Select CIS Controls (${mode^^})" \
            --checklist "Use [SPACE] to select, [ENTER] to confirm execution:" 22 78 12 \
            "${checklist_args[@]}" 3>&1 1>&2 2>&3)

        [[ -z "$choices" ]] && return
        eval "targets=($choices)"
    fi

    clear
    echo "================================================================="
    echo " CIS Framework Engine - Mode: ${mode^^} | Scope: ${scope^^}"
    echo "================================================================="
    echo ""

    local pass_count=0
    local fail_count=0

    for key in "${targets[@]}"; do
        local script_path="${MODULE_MAP[$key]}"
        local label="${MODULE_NAMES[$key]}"
        local sec="${MODULE_SECTIONS[$key]}"

        printf "[....] [Sec %s] %-42s " "$sec" "$label"

        # Capture both stdout and stderr instead of discarding to /dev/null
        local output
        if output=$(bash -c "source '$script_path' && $mode" 2>&1); then
            printf "\r\e[32m[PASS]\e[0m [Sec %s] %-42s\n" "$sec" "$label"
            ((pass_count++))
        else
            printf "\r\e[31m[FAIL]\e[0m [Sec %s] %-42s\n" "$sec" "$label"
            # Print detailed diagnostics if the control script emitted reasoning
            if [[ -n "$output" ]]; then
                echo -e "\e[33m${output}\e[0m"
            fi
            ((fail_count++))
        fi
    done

    echo ""
    echo "-----------------------------------------------------------------"
    echo " Summary: $pass_count Passed/Remediated | $fail_count Failed/Deficient"
    echo "-----------------------------------------------------------------"
    echo ""
    read -rp "Press [Enter] to return to the menu..."
}

# ------------------------------------------------------------------------------
# Menu System
# ------------------------------------------------------------------------------

show_scope_menu() {
    local mode="$1"
    while true; do
        local scope_choice
        scope_choice=$(whiptail --title "${mode^^} EXECUTION SCOPE" \
            --menu "Select execution scope:" 14 65 3 \
            "ALL"    "Run immediate ${mode} for ALL baseline controls" \
            "SELECT" "Checklist: select one or more specific controls" \
            "BACK"   "Return to primary menu" \
            3>&1 1>&2 2>&3)

        case "$scope_choice" in
            "ALL")    run_engine "$mode" "all" ;;
            "SELECT") run_engine "$mode" "select" ;;
            "BACK"|"") break ;;
        esac
    done
}

show_about() {
    whiptail --title "About RHEL CIS Framework" --msgbox \
"Script Name : RHEL CIS Baseline Automation Engine\n\
Author      : William Collison\n\
Architecture: Red Hat Enterprise Linux 8/9/10\n\n\
Organization:\n\
- Controls structured by CIS Benchmark sections (1-7)\n\
- Recursive dynamic discovery via find\n\
- Unified multi-select checklist without nested menu transitions." 16 68
}

main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "RHEL CIS HARDENING FRAMEWORK" \
            --menu "Author: William Collison\nSelect operation:" 16 65 4 \
            "AUDIT"  "Verify system configuration against baseline" \
            "HARDEN" "Apply remediation scripts to system controls" \
            "ABOUT"  "Display architecture and metadata" \
            "EXIT"   "Exit framework" \
            3>&1 1>&2 2>&3)

        case "$choice" in
            "AUDIT")  show_scope_menu "audit" ;;
            "HARDEN") show_scope_menu "harden" ;;
            "ABOUT")  show_about ;;
            "EXIT"|"") clear; exit 0 ;;
        esac
    done
}

main_menu
