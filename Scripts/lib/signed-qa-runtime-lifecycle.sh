#!/bin/zsh

qa_recover_interrupted_replacement() {
    local installed_app="$1"
    local staged_app="$2"
    local backup_app="$3"

    rm -rf "$staged_app"
    if [[ ! -e "$installed_app" && -e "$backup_app" ]]; then
        mv "$backup_app" "$installed_app"
    elif [[ -e "$installed_app" ]]; then
        rm -rf "$backup_app"
    fi
}

qa_unregister_installed_agent() {
    local installed_app="$1"
    local app_executable="$2"
    local command="$installed_app/Contents/MacOS/$app_executable"

    if [[ -x "$command" ]]; then
        "$command" --qa-unregister-agent
    fi
}

qa_stage_app_replacement() {
    local packaged_app="$1"
    local staged_app="$2"

    rm -rf "$staged_app"
    ditto "$packaged_app" "$staged_app"
}

qa_commit_app_replacement() {
    local installed_app="$1"
    local staged_app="$2"
    local backup_app="$3"

    rm -rf "$backup_app"
    if [[ -e "$installed_app" ]]; then
        mv "$installed_app" "$backup_app"
    fi
    mv "$staged_app" "$installed_app"
}

qa_rollback_app_replacement() {
    local installed_app="$1"
    local backup_app="$2"

    rm -rf "$installed_app"
    if [[ -e "$backup_app" ]]; then
        mv "$backup_app" "$installed_app"
    fi
}
