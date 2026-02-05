#!/bin/bash

# Create OpenSIPS database
opensipsdbctl create <<EOF
# If any database configuration is required, add here
EOF

# Wait a moment for db setup
sleep 1

# Create group and user for OpenSIPS
groupadd opensips
useradd -g opensips opensips
sleep 3

# Make sure the OpenSIPS service script is executable
chmod +x /etc/init.d/opensips

# Ensure OpenSIPS log directory exists
mkdir -p /var/log/opensips
touch /var/log/opensips.log
chown opensips:opensips /var/log/opensips /var/log/opensips.log
sleep 1

# Restart OpenSIPS if needed
# /etc/init.d/opensips restart

sleep 1

