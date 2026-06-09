#!/bin/sh
# Wait for WireGuard to be ready
sleep 5

# Run the iptables command
iptables -t nat -A POSTROUTING -d 192.168.1.0/24 -o eth1 -j MASQUERADE

# Keep the script running
tail -f /dev/null
