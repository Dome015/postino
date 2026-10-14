#!/bin/zsh
# Started only after download validation and the user's approval to quit.
# Arguments are passed directly through Process, never interpolated as shell code.
set -eu
[[ $# == 5 ]] || exit 1
target=$1 incoming=$2 backup=$3 parent_pid=$4 work_dir=$5
[[ "$target" == *.app && "${incoming:h}" == "${target:h}" && "${backup:h}" == "${target:h}" ]] || exit 1
[[ "${incoming:t}" == .Postino-incoming-*.app && "${backup:t}" == .Postino-backup-*.app ]] || exit 1
[[ "$parent_pid" == <-> && "${work_dir:t}" == PostinoUpdate-* ]] || exit 1
lock_dir="${target}.postino-update-lock"
locked=0
replaced=0
success=0
cleanup() {
    set +e
    if (( ! success && replaced )); then
        /bin/rm -rf "$target"
        /bin/mv "$backup" "$target"
    fi
    if (( ! success )); then
        # Do not launch a second normal instance if the old PID never quit.
        if ! /bin/kill -0 "$parent_pid" 2>/dev/null; then /usr/bin/open -n "$target" || true; fi
        /usr/bin/osascript -e 'display alert "Postino could not finish updating." message "Your previous version has been kept. Please try again."' || true
    fi
    /bin/rm -rf "$incoming"
    if (( locked )); then /bin/rmdir "$lock_dir" || true; fi
    /bin/rm -rf "$work_dir"
}
trap cleanup EXIT
/bin/mkdir "$lock_dir" || exit 1
locked=1
# Quit can be cancelled or stalled externally: never replace a running app.
for attempt in {1..240}; do
    /bin/kill -0 "$parent_pid" 2>/dev/null || break
    /bin/sleep 0.25
done
if /bin/kill -0 "$parent_pid" 2>/dev/null; then exit 1; fi
[[ -d "$target" && -d "$incoming" && ! -e "$backup" ]] || exit 1
/bin/mv "$target" "$backup"
replaced=1
/bin/mv "$incoming" "$target"
/usr/bin/open -n "$target"
success=1
/bin/rm -rf "$backup"
