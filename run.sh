#!/bin/sh
# Fix DMS greeter crash + deploy
set -e

echo "Fixing stale greeter directory ownership (UID shifted after thermald)..."
sudo chown -R greeter:greeter /var/lib/dms-greeter

echo "Removing stale greeter log..."
sudo rm -f /tmp/dms-greeter.log

echo "Resetting greetd start-limit so it can retry..."
sudo systemctl reset-failed greetd.service

echo "Deploying..."
just deploy

echo "Restarting greetd..."
sudo systemctl restart greetd.service