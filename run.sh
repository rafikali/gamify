#!/bin/bash
# Run learnify with Firebase dart-defines loaded from firebase.env.json
#
# Usage:
#   ./run.sh              # iOS simulator (default)
#   ./run.sh android      # Android emulator
#   ./run.sh chrome       # Web

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/firebase.env.json"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: firebase.env.json not found. Copy firebase.env.example.json and fill in your values."
  exit 1
fi

# Parse JSON and build --dart-define flags
DART_DEFINES=""
while IFS='=' read -r key value; do
  key=$(echo "$key" | tr -d '"' | xargs)
  value=$(echo "$value" | tr -d '"' | sed 's/,$//' | xargs)
  if [ -n "$key" ] && [ -n "$value" ]; then
    DART_DEFINES="$DART_DEFINES --dart-define=$key=$value"
  fi
done < <(grep ':' "$ENV_FILE" | sed 's/[{}]//g' | sed 's/": "/=/g')

DEVICE="${1:-}"
DEVICE_FLAG=""
if [ -n "$DEVICE" ]; then
  DEVICE_FLAG="-d $DEVICE"
fi

echo "Running with Firebase config from firebase.env.json..."
eval flutter run $DEVICE_FLAG $DART_DEFINES
