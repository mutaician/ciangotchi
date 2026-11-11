#!/bin/sh
# Daily refresh of every link source for the pet. A failure in one source
# never blocks the others.
D="$(dirname "$0")"
sh "$D/refresh-fmhy.sh"
sh "$D/refresh-youtube.sh"
sh "$D/refresh-x.sh" >/dev/null 2>&1
exit 0
