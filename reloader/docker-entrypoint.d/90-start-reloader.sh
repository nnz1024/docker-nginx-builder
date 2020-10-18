#!/bin/sh

set -e

ME=$(basename $0)

ERROR="$ME: error: cannot activate reloader"
WARNING="$ME: warning"
INFO="$ME: info"

RELOADER='/reloader/reloader.sh'
RELOADER_HEAVY='/reloader/reloader-heavy.sh'

DEFAULT_WATCH_PERIOD='5'

WATCH_LIST="${WATCH_LIST:-/etc/nginx}"

WATCH_EVENTS="${WATCH_EVENTS:-modify,move,create,delete,move_self,delete_self}"

FLOAT_REGEXP='^[0-9]\+\(\.[0-9]*\)\?$'
ZERO_REGEXP='^\(-t\)\?0\+\(\.0*\)\?$'

INOTIFY_KEYS='e'

WATCH_TS="${WATCH_TS:-%Y/%M/%d %H:%m:%S}"

WATCH_LOCK="${WATCH_LOCK:-/tmp/reloader}"

die() {
    if [ -z "$WATCH_IGNORE_ERRORS" ]; then
        # We (and parent) have -e set, so we don't need to kill PPID to fail ENTRYPOINT
        exit 1
    fi
    # Nginx will run, reloader will not
    exit 0
}

if [ ! -x "$(which inotifywait)" ]; then
    echo >&3 "$ERROR: package inotify-tools is missing"
    die
fi

# If entrypoint is not dumb-init, thing may go wrong. Nginx cares only about
# its children, not about our reloader script. We need a minimal init which
# can correctly forward signals and reap dead processes.
if ! grep -q dumb-init /proc/1/cmdline; then
    echo >&3 "$ERROR: init does not look like dumb-init. Please add dumb-init to ENTRYPOINT:" \
        'ENTRYPOINT ["/usr/bin/dumb-init", "--", "/docker-entrypoint.sh"]'
    die
fi

if [ -n "$WATCH_HEAVY" ]; then
    echo >&3 "$INFO: using heavy reloader (may cause significant system load)"
    RELOADER="$RELOADER_HEAVY"
    # Add extra level of silence to inotifywait
    INOTIFY_KEYS="q$INOTIFY_KEYS"
else
    # Enable monitor mode for inotifywait
    INOTIFY_KEYS="m$INOTIFY_KEYS"
fi

if [ ! -x "$RELOADER" ]; then
    if [ -f "$RELOADER" ]; then
        echo >&3 "$ERROR: $RELOADER is not executable"
    else
        echo >&3 "$ERROR: $RELOADER is missing"
    fi
    die
fi

if [ -n "$WATCH_RECURSIVE" ]; then
    INOTIFY_KEYS="r$INOTIFY_KEYS"
fi

if ! date "+$WATCH_TS" > /dev/null 2>&1; then
    echo >&3 "$ERROR: '$WATCH_TS' is not a correct time format"
fi

# Reloader always writes to stderr, because stdout very often is feed 
# to some log analyser configured for specific log format.
# Difference between FDs 4 and 5 only in verbosity:
# FD 4 is "info" messages (which can be handy for testing and debug)
# FD 5 is "error" messages (suppressing them is strongly discouraged)
if [ -z "$WATCH_FULLY_QUIET" ]; then
    exec 5>&2
else # Suppress even errors
    exec 5>/dev/null
    WATCH_QUIET=1
fi
if [ -z "$WATCH_QUIET" ]; then
    exec 4>&2
else
    exec 4>/dev/null
    INOTIFY_KEYS="q$INOTIFY_KEYS"
fi

if [ -n "$WATCH_RESTART" ]; then
    if ! echo "$WATCH_RESTART" | grep -q "$FLOAT_REGEXP"; then
        echo >&3 "$WARNING: incorrect watch restart delay '$WATCH_RESTART', setting to $DEFAULT_WATCH_PERIOD"
        WATCH_RESTART="$DEFAULT_WATCH_PERIOD"
    fi
    if echo "$WATCH_RESTART" | grep -q "$ZERO_REGEXP"; then
        echo >&3 "$WARNING: watch restart delay cannot be zero, setting to $DEFAULT_WATCH_PERIOD"
        WATCH_RESTART="$DEFAULT_WATCH_PERIOD"
    fi
    echo >&3 "$INFO: if inotify fails, it will be restarted after $WATCH_RESTART seconds"
fi

WATCH_PERIOD="${WATCH_PERIOD:-$DEFAULT_WATCH_PERIOD}"
if [ -z "$WATCH_HEAVY" ] && timeout -t1 true 2>/dev/null 1>&2; then
    # It's heavy mode and old busybox "timeout".
    # Check as integer, since it isn't accept float. Negation must be outside of "test", not inside
    # (if WATCH_PERIOD will not be a correct integer, test will simply fail instead of evaluating
    # comparison as a false and then negate it to true)
    if ! [ "$WATCH_PERIOD" -ge 0 ] 2>/dev/null; then
        echo >&3 "$WARNING: incorrect watch period '$WATCH_PERIOD', setting to $DEFAULT_WATCH_PERIOD"
        WATCH_PERIOD="$DEFAULT_WATCH_PERIOD"
    fi
    # Add -t key, required by busybox "timeout" syntax
    WATCH_PERIOD="-t$WATCH_PERIOD"
else
    # It's a GNU "timeout", which accepts float, or a heavy mode, where "sleep" accepts floats both
    # in busybox and coreutils
    if ! echo "$WATCH_PERIOD" | grep -q "$FLOAT_REGEXP"; then
        echo >&3 "$WARNING: incorrect watch period '$WATCH_PERIOD', setting to $DEFAULT_WATCH_PERIOD"
        WATCH_PERIOD="$DEFAULT_WATCH_PERIOD"
    fi
fi

if echo "$WATCH_PERIOD" | grep -q "$ZERO_REGEXP"; then
    echo >&3 "$WARNING: watch period cannot be 0, setting to $DEFAULT_WATCH_PERIOD"
    WATCH_PERIOD="$DEFAULT_WATCH_PERIOD"
fi

if [ -n "$WATCH_SEPARATOR" ]; then
    echo >&3 "$INFO: using '$WATCH_SEPARATOR' as path list separator"
    export IFS="$WATCH_SEPARATOR"
fi

for it in $WATCH_LIST; do
    # Strip leading @ from names for the check, allowing to pass excludes to inotifywait
    if [ ! -e "${it#@}" ]; then
        echo >&3 "$ERROR: incorrect path '${it#@}'"
        die
    fi
done

export INOTIFY_KEYS WATCH_EVENTS WATCH_LIST WATCH_PERIOD WATCH_RESTART WATCH_TS WATCH_LOCK

"$RELOADER" 1>&4 2>&5 &
