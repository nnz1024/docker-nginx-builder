#!/bin/sh

if [ -z "$INOTIFY_KEYS" -o -z "$WATCH_EVENTS" -o -z "$WATCH_LIST" \
        -o -z "$WATCH_TS" -o -z "$WATCH_LOCK" ]; then
    echo >&2 "$(date "+$WATCH_TS") $0: incorrect environment, exiting. Check start script"
    exit
fi

while true; do
    LINE="$(inotifywait "-$INOTIFY_KEYS" "$WATCH_EVENTS" $WATCH_LIST)"
    if [ "$?" -ne '0' ]; then
        if [ -n "$WATCH_RESTART" ]; then
            echo >&2 "$(date "+$WATCH_TS") $0: inotifywait failed, restarting"
            sleep "$WATCH_RESTART" # Limit respawning
            continue
        else
            break
        fi
    fi
    echo "$(date "+$WATCH_TS") $0: inotify reports: $LINE"
    while true; do
        # Add timeout and embrace silencing
        LINE="$(inotifywait -t "$WATCH_PERIOD" "-$INOTIFY_KEYS" "$WATCH_EVENTS" \
            $WATCH_LIST)"
        STATUS="$?"
        if [ "$STATUS" -eq "0" ]; then
            if [ -n "$LINE" ]; then # If we have something to report...
                echo "$(date "+$WATCH_TS") $0: inotify reports: $LINE"
            fi # Else just continue to listen
        elif [ "$STATUS" -eq "2" ]; then # Watch timeout, nothing happened
            break
        else
            echo >&2 "$(date "+$WATCH_TS") $0: inotifywait failed, wait and reload"
            sleep "$WATCH_PERIOD"
            break
        fi
    done
    echo "$(date "+$WATCH_TS") $0: something changed, testing config"
    if TEST=$(nginx -qt 2>&1); then
        echo "$(date "+$WATCH_TS") $0: config looks OK, reloading"
        nginx -s reload
    else
        echo >&2 "$(date "+$WATCH_TS") $0: config incorrect, ignoring"
        # The first line contains correct timestamp and error meassage,
        # second one duplicates this message without timestamp,
        # and the third is common fail message, so print only first one
        echo "$TEST" | head -n1 >&2
    fi
done

echo >&2 "$(date "+$WATCH_TS") $0: inotifywait failed, stopping nginx"
kill -s ABRT 1 # Failure with code 128+6=134 (or 137, if dump-init remaps 6->9)
# If you don't want to get failure exit status, comment the previous line,
# and uncomment the next one:
#nginx -s quit # Clean exit with code 0
exit # Return value does not have much meaning, dumb-init proxies Nginx exit status
