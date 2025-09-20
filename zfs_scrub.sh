#!/bin/bash

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 [--check] <zfs_mirror_name> | --test"
    exit 1
fi

# --- Check mode for test automation ---
if [ "$1" == "--check" ]; then
    POOL="$2"
    if zpool status "$POOL" | grep -q "scrub in progress"; then
        echo "A scrub is already running on pool: $POOL"
        exit 0
    else
        echo "No scrub running on pool: $POOL"
        exit 1
    fi
fi

# --- Test mode ---
if [ "$1" == "--test" ]; then
    for cmd in zfs zpool losetup dd awk; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo "Error: $cmd command not found. Please install required utilities."
            exit 1
        fi
    done

    if ! lsmod | grep -q "^zfs"; then
        echo "ZFS kernel module not loaded. Attempting to load with sudo modprobe zfs..."
        if ! sudo modprobe zfs; then
            echo "Error: Failed to load ZFS kernel module. Please ensure ZFS is installed and the kernel module is available."
            exit 1
        fi
    fi

    TEST_POOL="scrubstat_testpool"
    TMP1="/tmp/scrubstat_testfile1"
    TMP2="/tmp/scrubstat_testfile2"
    LOOP1=""
    LOOP2=""
    MNT="/tmp/scrubstat_mnt"

    echo "Setting up test ZFS mirror pool with loop devices..."

    sudo zpool destroy "$TEST_POOL" 2>/dev/null || true
    # Only remove our specific loop devices and files, not all
    sudo rm -f "$TMP1" "$TMP2"
    sudo rm -rf "$MNT"

    TMP_AVAIL=$(df --output=avail -m /tmp | tail -1 | tr -d ' ')
    LOOP_TOTAL_MB=$((TMP_AVAIL * 80 / 100))
    LOOP_FILE_MB=$((LOOP_TOTAL_MB / 2))

    if [ "$LOOP_FILE_MB" -lt 1024 ]; then
        echo "Not enough space in /tmp for test (need at least 2GB total)."
        exit 1
    fi

    echo "Creating two loop files of size ${LOOP_FILE_MB}MB each in /tmp..."

    sudo dd if=/dev/zero of="$TMP1" bs=1M count="$LOOP_FILE_MB" status=none
    sudo dd if=/dev/zero of="$TMP2" bs=1M count="$LOOP_FILE_MB" status=none

    LOOP1=$(sudo losetup --show -f "$TMP1")
    LOOP2=$(sudo losetup --show -f "$TMP2")

    sudo zpool create -f "$TEST_POOL" mirror "$LOOP1" "$LOOP2"
    sudo mkdir -p "$MNT"
    sudo zfs set mountpoint="$MNT" "$TEST_POOL"

    POOL_AVAIL=$(sudo zfs get -Hp -o value available "$TEST_POOL")
    if [[ "$POOL_AVAIL" =~ ^[0-9]+$ ]]; then
        POOL_AVAIL_MB=$((POOL_AVAIL / 1024 / 1024))
    else
        UNIT=${POOL_AVAIL: -1}
        VALUE=${POOL_AVAIL%?}
        case "$UNIT" in
            T|t) POOL_AVAIL_MB=$(awk "BEGIN {print int($VALUE * 1024 * 1024)}") ;;
            G|g) POOL_AVAIL_MB=$(awk "BEGIN {print int($VALUE * 1024)}") ;;
            M|m) POOL_AVAIL_MB=$(awk "BEGIN {print int($VALUE)}") ;;
            K|k) POOL_AVAIL_MB=$(awk "BEGIN {print int($VALUE / 1024)}") ;;
            *) POOL_AVAIL_MB=0 ;;
        esac
    fi

    FILL_MB=$((POOL_AVAIL_MB * 90 / 100))
    FILE_MB=$((FILL_MB / 10))

    if [ "$FILE_MB" -lt 1 ]; then
        echo "Not enough space in pool for test files."
        sudo zpool destroy "$TEST_POOL"
        sudo losetup -d "$LOOP1" || true
        sudo losetup -d "$LOOP2" || true
        sudo rm -f "$TMP1" "$TMP2"
        sudo rm -rf "$MNT"
        exit 1
    fi

    echo "Writing 10 files of ${FILE_MB}MB random data each to the pool (total: ${FILL_MB}MB)..."
    for i in {1..10}; do
        sudo dd if=/dev/urandom of="$MNT/file_$i" bs=1M count="$FILE_MB" status=none
    done

    echo "Triggering scrub via main script..."
    sudo bash "$0" "$TEST_POOL" &
    SCRUB_PID=$!

    sleep 1

    echo
    echo "Testing detection of already running scrub..."
    sudo bash "$0" --check "$TEST_POOL" && echo "Already running detection: OK" || echo "Already running detection: FAIL"

    echo "Waiting for scrub to complete..."
    wait $SCRUB_PID

    if sudo zpool status "$TEST_POOL" | grep -q "scrub in progress"; then
        echo "Scrub completion detection: FAIL"
    else
        echo "Scrub completion detection: OK"
    fi

    echo "Cleaning up test pool and files..."
    sudo zpool destroy "$TEST_POOL"
    sudo losetup -d "$LOOP1" || true
    sudo losetup -d "$LOOP2" || true
    sudo rm -f "$TMP1" "$TMP2"
    sudo rm -rf "$MNT"

    echo "Test completed."
    exit 0
fi

POOL="$1"

if zpool status "$POOL" | grep -q "scrub in progress"; then
    echo "A scrub is already running on pool: $POOL"
    started_by_script=0
else
    echo "Starting scrub on pool: $POOL"
    zpool scrub "$POOL"
    started_by_script=1
fi

# Print zpool status in place until scrub is done
lines_printed=0
while true; do
    status=$(zpool status "$POOL")
    lines=$(echo "$status" | wc -l)
    # Move cursor up and clear lines if not the first iteration
    if [ $lines_printed -gt 0 ]; then
        for ((i=0; i<lines_printed; i++)); do
            printf "\033[F\033[2K"
        done
    fi
    echo "$status"
    lines_printed=$lines
    if ! echo "$status" | grep -q "scrub in progress"; then
        break
    fi
    sleep 1
done

echo
echo "Scrub completed."
echo "Final ZFS scrub status:"
zpool status "$POOL"
