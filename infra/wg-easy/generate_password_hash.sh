#!/bin/bash

# Script to generate password hash for wg-easy
# The hash will have double $$ for docker-compose compatibility

set -e

echo "WG-Easy Password Hash Generator"
echo "================================"
echo ""

# Prompt for password (masked input)
read -s -p "Enter password: " PASSWORD
echo ""
read -s -p "Confirm password: " PASSWORD_CONFIRM
echo ""

# Check if passwords match
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Error: Passwords do not match!"
    exit 1
fi

# Check if password is not empty
if [ -z "$PASSWORD" ]; then
    echo "Error: Password cannot be empty!"
    exit 1
fi

echo ""
echo "Generating password hash..."

# Generate hash using the wg-easy docker image
# The image uses bcrypt via Node.js
HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$PASSWORD")

# Check if hash generation was successful
if [ -z "$HASH" ]; then
    echo "Error: Failed to generate password hash!"
    exit 1
fi

# Replace single $ with $$ for docker-compose
ESCAPED_HASH=$(echo "$HASH" | sed 's/\$/\$\$/g')

echo ""
echo "$ESCAPED_HASH"
