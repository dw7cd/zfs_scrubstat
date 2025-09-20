## What is This?

This is a simple script that is intended to provide a progress bar for ZFS scrub operations. Useful when you want the scrub to run in a terminal and continuously show you progress without having to re-query with 'zpool status'.

## How to Use it?

Run the script as: 'sudo ./zfs_scrub.sh <your_pool_name>'

It will start a scrub if one is not already running. If a scrub is already running, it will start displaying its progress. Killing the script does not affect the scrub that was started. If you want to stop the scrub use the usual 'zpool scrub -s'. 
