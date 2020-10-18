#!/bin/sh

if [ -z "$INOTIFY_KEYS" -o -z "$WATCH_EVENTS" -o -z "$WATCH_LIST" -o \
        -z "$WATCH_PERIOD" -o -z "$WATCH_TS" -o -z "$WATCH_LOCK" ]; then
    echo >&2 "$(date "+$WATCH_TS") $0: incorrect environment, exiting. Check start script"
    exit
fi

EVENT_FLAG=''
while true; do
    inotifywait "-$INOTIFY_KEYS" "$WATCH_EVENTS" $WATCH_LIST
    if [ -n "$WATCH_RESTART" ]; then
        echo >&2 "$(date "+$WATCH_TS") $0: inotifywait failed, restarting"
        sleep "$WATCH_RESTART" # Limit respawning
    else
        echo >&2 "$(date "+$WATCH_TS") $0: inotifywait failed, stopping nginx"
        # We have one main shell and two (at least) subshells (we are inside one of them),
        # speaking nothing about Nginx. To stop all the things, send destructive signal
        # to dumb-init (but not 9, PID 1 will not receive it), which will forward it 
        # to Nginx, which in its turn will exit with non-zero code, and dumb-init will
        # send SIGTERM to the remaining processes. Use 6 (ABRT) as the closest in meaning.
        # Yep, I don't want to parse /proc/$$/stat to extract the session (leader) ID,
        # and use dumb-init as a free delivery service.
        kill -s ABRT 1 # Failure with code 128+6=134 (or 137, if dump-init remaps 6->9)
        # If you don't want to get failure exit status, comment the previous line,
        # and uncomment the next one:
        #nginx -s quit # Clean exit with code 0
        exit # Return value does not have much meaning, dumb-init proxies Nginx exit status
    fi
done | while true; do
    # Wait $WATCH_PERIOD for new events
    LINE="$(timeout "$WATCH_PERIOD" cat -)" 2>/dev/null
    if [ -n "$LINE" ]; then
        # Something happened in last $WATCH_PERIOD
        EVENT_FLAG='y' # Raise the EVENT_FLAG
        # Eliminate newlines and company regardless of IFS value
        echo "$(date "+$WATCH_TS") $0: inotify reports:" \
            "$(echo "$LINE" | tr '[:space:]' ' ')"
    elif [ "$EVENT_FLAG" = 'y' ]; then
        # Nothing happened in last $WATCH_PERIOD, but something was 
        # in the previous one
        EVENT_FLAG='' # Lower the flag
        echo "$(date "+$WATCH_TS") $0: something changed, testing config"
        if TEST=$(nginx -qt 2>&1); then
            echo "$(date "+$WATCH_TS") $0: config looks OK, reloading"
            nginx -s reload
        else
            echo >&2 "$(date "+$WATCH_TS") $0: config incorrect, ignoring"
            # The first line contains correct timestamp and error meassage,
            # second one duplicates this message without timestamp,
            # and third one is common fail message, so print only first one
            echo "$TEST" | head -n1 >&2
        fi
    fi
done
