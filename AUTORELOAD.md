# Automatically reload Nginx on config change

This reloader watches for Nginx configuration files via inotify and, when something
changes, performs syntax check and reloads Nginx if syntax is OK.

# How to enable it?

Build image with `Dockerfile.autoreload`:
```
docker build . -f Dockerfile.autoreload --build-arg="NGINX_VERSION=1.19.1" -t "your-repo/nginx:1.19.1-custom"
```
and run with appropriate settings:
```
docker run -d --rm -p 80:80 -v ~/work/nginx:/etc/nginx/ -e WATCH_LIST="/etc/nginx" "your-repo/nginx:1.19.1-custom"
```

# Settings

* `WATCH_LIST` — list of watched files and/or directories. Separated by space by default but,
    if you need to watch for paths with spaces, you can set `WATCH_SEPARATOR` to any
    other symbol, `:` for example. You can also add excludes using `@` symbol, for example,
    `WATCH_LIST='/etc/nginx @/etc/nginx/conf.d`. **It is strongly advised to watch for directories,
    but not for files, because files can be deleted during update process, and inotifywait will
    lose watch on them!** By default, `WATCH_LIST=/etc/nginx`.
* `WATCH_SEPARATOR` — list of symbols considered as a separator in `WATCH_LIST`. By default,
    shell's IFS is used (which usually includes space, tabulation and newline).
* `WATCH_HEAVY` — use heavy algorithm instead of light one (see algorithms description
    below). Set to any non-empty value to activate the mode.
* `WATCH_PERIOD` — time span (in seconds) used by reloading algorithms to avoid unnecessary reloads.
    Must be a positive float. Meaning is different depending on the algorithm (see below). The common
    point that Nginx will not receive configuration updates more often than this period. Default value
    `WATCH_PERIOD=5`.
* `WATCH_EVENTS` — list of events inotifywait will listen for. By default, list in very inclusive
    (`modify,move,create,delete,move_self,delete_self`), but it is strongly recommended to watch
    for specifical, non-duplicating event depending of your config update process
    (in mostly cases, `moved_to` suits well, if you are watching for config directory).
* `WATCH_RECURSIVE` — watch for all files and subdirectories inside dirs listed in `WATCH_LIST`.
    It is mostly useless for files, but can be useful for directories. Set to any non-empty
    value to activate the mode.
* `WATCH_QUIET` — do not print anything to console if everything is OK. Print only errors.
    Set to any non-empty value to activate the mode.
* `WATCH_FULLY_QUIET` — suppress error messages as well as informational ones. Not recommended.
    Set to any non-empty value to activate the mode.
* `WATCH_TS` — timestamp format for log messages. By default, `WATCH_TS='%Y/%M/%d %H:%m:%S'`,
    which mimics Nginx error log timestamp format.
* `WATCH_IGNORE_ERRORS` — on startup phase, check of all settings listed here will be performed.
    By default, if something is wrong, container startup will be failed with code 1. If you'll
    set this to any non-empty value, in the case of errors, container will run with Nginx,
    but without reloader.
* `WATCH_RESTART` — restart inotifywait if it fails (disabled by default). Specify any positive float
    number to enable restarting with delay defined by this number (in seconds). Set to any non-number
    value to activate the mode with default delay (5 seconds). It is recommended to enable this mode 
    if you are watching for files (also implicitly implies by recursive ectory watching) but aren't 
    watching for `delete_self`. In this case, `inotifywait` will fail if file (or directory) it watching
    will be deleted. So, in this particular case, `WATCH_RESTART` can be useful (in conjunction with 
    `WATCH_QUIET`). Or simply do not watch for files!

# Logging

Reloader has two kinds of runtime messages: informational ones (useful for test, debug
and monitoring), and error (+ warning) ones, which usually you must see in any case. 
**All of them** will be sent to container's STDERR because STDOUT very often is fed 
to some Nginx log analyzer, which won't be happy with free-form text messages.

Exception is startup messages, which follows to the common rules for entrypoint script from
[official Nginx dockerization](https://github.com/nginxinc/docker-nginx/): if 
`NGINX_ENTRYPOINT_QUIET_LOGS` is set to non-empty value, all startup messages will be sent to
`/dev/null`, or to STDOUT otherwise.

Back to the runtime messages, you can silence informational ones with `WATCH_QUIET=1`
(as well as inotifywait's chatter: "Establishing watches..." etc), or suppress all
messages from reloader with `WATCH_FULLY_QUIET=1`. The last one in strongly not recommended,
because if some problem occurs, it will be very hard to detect the fail and find the source.

Also, you can set `WATCH_TS` to customize timestamps in reloader's log messages
(see FORMAT section in `man 1 date` for syntax description).

# Using with other Alpine images

This reloader designed primarily for docker-nginx-builder, which produces Debian-based Nginx
images. However, it also can be use used on top of official Alpine-based nginx images.
Example Dockerfile:
```
ARG NGINX_VERSION=1.19.3
FROM nginx:${NGINX_VERSION}-alpine

RUN apk add --no-cache inotify-tools dumb-init

COPY reloader /

ENTRYPOINT ["/usr/bin/dumb-init", "-v", "--", "/docker-entrypoint.sh"]

CMD ["nginx", "-g", "daemon off;"]
```

Please note that with some old Busybox versions, like 1.28, `WATCH_PERIOD` in light mode 
must be an integer. This problem **do not** occur with official Nginx 1.18-alpine and
1.19-alpine, because they are based on Alpine 3.11 with Busybox 1.31. Anyway, startup
script will perform check and warn you if need.

If you are planning to use this reloader in your custom image, make sure that entrypoint will
start `/docker-entrypoint.d/90-start-reloader.sh` with privileges sufficient to get read
access to paths you plan to watch.

# Algorithms: light or heavy?

Task "watch the files and reload Nginx if something changes" is not so simple at it looks
and may require some manual tuning and testing before using auto-reloader in the production setup.
The problem is: very often config files are updated not in one atomic operation, but via sequence
of different actions (CREATE, MOVE, DELETE, MODIFY). For example, let's see how it goes
with `vim` (for simplicity, vim was configured to write swapfiles in separate directory,
and `nobk` mode is enabled):
```
/etc/nginx/ CREATE 4913
/etc/nginx/ DELETE 4913
/etc/nginx/ MOVED_FROM nginx.conf
/etc/nginx/ MOVED_TO nginx.conf~
/etc/nginx/ CREATE nginx.conf
/etc/nginx/ MODIFY nginx.conf
/etc/nginx/ MODIFY nginx.conf
/etc/nginx/ DELETE nginx.conf~
```
Another example is Kubernetes ConfigMap update (NB: it works only if you mount volume
into pod as entire directory, i.e. without `subPath`):
```
/etc/nginx/ OPEN,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/..2020_08_01_10_16_18.747077977/ OPEN,ISDIR 
/etc/nginx/ ACCESS,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/..2020_08_01_10_16_18.747077977/ ACCESS,ISDIR 
/etc/nginx/ ACCESS,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/..2020_08_01_10_16_18.747077977/ ACCESS,ISDIR 
/etc/nginx/ CLOSE_NOWRITE,CLOSE,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/..2020_08_01_10_16_18.747077977/ CLOSE_NOWRITE,CLOSE,ISDIR 
/etc/nginx/..2020_08_01_10_16_18.747077977/ OPEN nginx.conf
/etc/nginx/..2020_08_01_10_16_18.747077977/ ACCESS nginx.conf
/etc/nginx/..2020_08_01_10_16_18.747077977/ CLOSE_NOWRITE,CLOSE nginx.conf
/etc/nginx/ CREATE,ISDIR ..2020_08_01_10_17_29.512424676
/etc/nginx/ ATTRIB,ISDIR ..2020_08_01_10_17_29.512424676
/etc/nginx/ OPEN,ISDIR ..2020_08_01_10_17_29.512424676
/etc/nginx/ CREATE ..data_tmp
/etc/nginx/ ACCESS,ISDIR ..2020_08_01_10_17_29.512424676
/etc/nginx/ MOVED_FROM ..data_tmp
/etc/nginx/ MOVED_TO ..data
/etc/nginx/ CLOSE_NOWRITE,CLOSE,ISDIR ..2020_08_01_10_17_29.512424676
/etc/nginx/ OPEN,ISDIR 
/etc/nginx/ OPEN,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/..2020_08_01_10_16_18.747077977/ OPEN,ISDIR 
/etc/nginx/ ACCESS,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/..2020_08_01_10_16_18.747077977/ ACCESS,ISDIR 
/etc/nginx/ ACCESS,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/..2020_08_01_10_16_18.747077977/ ACCESS,ISDIR 
/etc/nginx/..2020_08_01_10_16_18.747077977/ DELETE nginx.conf
/etc/nginx/ CLOSE_NOWRITE,CLOSE,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/..2020_08_01_10_16_18.747077977/ CLOSE_NOWRITE,CLOSE,ISDIR 
/etc/nginx/..2020_08_01_10_16_18.747077977/ DELETE_SELF 
/etc/nginx/ DELETE,ISDIR ..2020_08_01_10_16_18.747077977
/etc/nginx/ CLOSE_NOWRITE,CLOSE,ISDIR 
```

On the other side, if you firstly edit config outside watched directory, and then copy
or move it here with `cp` or `mv`, things are getting easier:
```
/etc/nginx/ MODIFY nginx.conf
```
in case of `cp` and
```
/etc/nginx/ MOVED_TO nginx.conf
```
in case of `mv`. However, things are becoming complicated again, if you need to update
several files in one "transaction".

So, application cannot surely know when will be the "last" event, after which it can
safely load configs (and they will be in consistent). That's the reason why the most
of modern applications still doesn't use inotify and requires explicit reloading
(or have strict requirement how config updates must be performed — e.g. Envoy).

And, vice versa, servers like Nginx usually reloads config in an asynchronous manner,
so your config update system cannot surely know that server does not reading its config
at this moment.

However, if you've read this so far, probably in your specific case manual reloading
brings too many problems, and you will agree to a bit dirty ad-hoc solution. Well, there
are at least two approaches:

## Light mode (default)

1. `inotifywait` started in monitor mode (watching for files continuously).
1. Every `$WATCH_PERIOD` seconds reloader read event log from inotify.
1. If something happened with files, reloader would remember this, but do nothing.
1. If nothing happened on this iteration and nothing on the previous one, reloader
    do nothing.
1. If nothing happened on this iteration, but something on the previous one,
    reloader will test the config syntax and if it is correct, reload Nginx.

What does it give us? At the moment of reloading starts, no changes in configs was
made in last `WATCH_PERIOD`. This does not guarantee, but it does provide a high
probability that configuration files update is already finished. However, it
cannot eliminate the risk that another update begins when config reloading
will be in progress, so be careful and don't update your configs too frequently.
`3*WATCH_PERIOD` may be a good minimal period.

This method also has at least two disadvantages. First, if reloader will watch
for some file (e.g. `/etc/nginx/nginx.conf`), and that file will be deleted in
the process of the update (for example, `vim` usually updates files via deletion),
reloader will lose control of them (or, if you set `WATCH_EVENTS` not to
include `delete_self`, `inotifywait` will fail). To prevent this, try to
watch for directories (e.g. `WATCH_LIST="/etc/nginx /etc/nginx/conf.d"`)
and not to use `WATCH_RECURSIVE`. Another downside is periodically spawning
and dying processes `timeout` and `cat` (required for "batch reading", because
POSIX `sh` does not have timeout support in `read` builtin).

## Heavy mode (WATCH_HEAVY)

1. `inotifywait` started in wait mode (report and exit after first event).
1. After getting message about this event, reloader will start the inner loop:
    1. Run `inotifywait` with `WATCH_PERIOD` timeout.
    1. If its exit code is 2 (timeout exceeded, and nothing happened in that
        period), stop the loop.
    1. If exit code is 0 (something happened), continue the loop.
    1. Otherwise (`inotifywait` failed for some reason), sleep
        for `WATCH_PERIOD` and stop the loop (hoping that problem is gone).
1. Reloader will test the config syntax and if it is correct, reload Nginx.
1. Go to point 1.
    
Advantages? No spawning processes (except for inner loop and config update, 
but it happens only after configuration changes) — only `inotifywait`. And 
no loose-on-delete files, because watches are re-established after every update.
(But remember, `inotifwait` still will complain about deleting files if `delete_self`
aren't in `WATCH_EVENTS`, so enable `WATCH_RESTART=1` in this case.)

Downsides? If you have many configuration directories, there can be a performance
and system load impact, caused re-establishing of watches every time. Using
`WATCH_RECURSIVE` in this mode is not recommended.

So, choose wisely. Investigate your own case, perform some tests, choose
optimal parameter values. There is no magic pill suitable in every situation.
