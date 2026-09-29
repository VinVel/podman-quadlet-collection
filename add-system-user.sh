#!/usr/bin/env sh

# This script takes one positional argument for the name of the system-user
# The home directory of the home user will be situated under /var/lib/system-user
# Additionally, it will create a btrfs subvolume if on an btfrs host.
# 
# After that, it enables lingering for the newly-created system-user
# To interact with the newly created user, you can e.g. use the following command:
# $ sudo -u system-user bash

if [ "$#" -lt 1 ] || [ "$#" -gt 1 ]; then
    echo "Usage: add-system-user.sh <name of the system-user>" >&2
    exit 1
fi 

echo "Creating a system-user with the name '$1'"

sudo useradd --system \
    --btrfs-subvolume-home \
    --create-home \
    --shell /usr/sbin/nologin \
    --home-dir "/var/lib/$1" \
    --add-subids-for-system \
    "$1"

echo "Enabling lingering for system-user '$1'"

sudo loginctl enable-linger "$1"