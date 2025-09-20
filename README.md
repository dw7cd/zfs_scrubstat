## What is This?

This is a simple script that is intended to provide a progress bar for ZFS scrub operations. Useful when you want the scrub to run in a terminal and continuously show you progress without having to re-query with 'zpool status'.

## How to Use it?

Run the script as: 'sudo ./zfs_scrub.sh <your_pool_name>'

It will start a scrub if one is not already running. If a scrub is already running, it will start displaying its progress. Killing the script does not affect the scrub that was started. If you want to stop the scrub use the usual 'zpool scrub -s'. 

If you wish to run the test, run the script with 'sudo ./zfs_scrub.sh --test'. This will create a pair of loopback files in your /tmp taking up 80% of your free /tmp space, then fill 90% of that with random data. Then it will test the script functionality using this temp data, and clean up after itself.

Final option is to just query whether a scrub is currently running. To do this, run 'sudo ./zfs_scrub.sh --check <your_pool_name>'. It is mostly intended for the test option, but exists.
