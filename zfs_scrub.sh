#!/bin/bash

set -e

# Check for superuser privileges
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root or with sudo."
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <zfs_mirror_name>"
    exit 1
fi

POOL="$1"

get_scrub_status() {
    zpool status "$POOL" | awk '
        /scrub in progress/ {
            pct = 0
            for (i=1; i<=NF; i++) {
                if ($i ~ /%/) {
                    gsub(/[^0-9]/, "", $i)
                    pct = $i
                    break
                }
            }
            print pct
            exit
        }
        /scrub repaired/ || /scrub completed/ {
            print "done"
            exit
        }
    '
}

if zpool status "$POOL" | grep -q "scrub in progress"; then
    echo "A scrub is already running on pool: $POOL"
    started_by_script=0
else
    echo "Starting scrub on pool: $POOL"
    zpool scrub "$POOL"
    started_by_script=1
fi

# Graceful in-place update of zpool status without blinking
prev_lines=()
first_run=1
while true; do
    status=$(zpool status "$POOL")
    IFS=$'\n' read -r -a curr_lines <<<"$status"
    lines=${#curr_lines[@]}

    # Move cursor up to the start of the block (if not first iteration)
    if [ $first_run -eq 0 ]; then
        printf "\033[%dA" "${#prev_lines[@]}"
    fi

    # Print each line, always print on first run or if line count changed
    if [ $first_run -eq 1 ] || [ ${#prev_lines[@]} -ne $lines ]; then
        for ((i=0; i<lines; i++)); do
            printf "\033[2K%s\n" "${curr_lines[$i]}"
        done
    else
        for ((i=0; i<lines; i++)); do
            if [ "${curr_lines[$i]}" != "${prev_lines[$i]}" ]; then
                printf "\033[2K%s\n" "${curr_lines[$i]}"
            else
                printf "\033[E"
            fi
        done
    fi

    # If new output is shorter, clear remaining old lines
    if [ ${#prev_lines[@]} -gt $lines ]; then
        for ((i=lines; i<${#prev_lines[@]}; i++)); do
            printf "\033[2K\n"
        done
    fi

    prev_lines=("${curr_lines[@]}")
    first_run=0

    if ! echo "$status" | grep -q "scrub in progress"; then
        break
    fi
    sleep 1
done

echo
echo "Scrub completed."
echo "Final ZFS scrub status:"
zpool status "$POOL"
