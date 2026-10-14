#!/usr/bin/env bash
# Plays the start of an online match between two headless copies of the game
# (see tests/net_test.gd). Exits non-zero if either side fails a check.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-7790}"
# RELAY=1 plays through a local copy of the relay server (needs Node and
# `npm install` in relay/) instead of connecting directly.
RELAY_PID=""
if [ "${RELAY:-0}" = "1" ]; then
  RELAY_PORT=$((PORT + 1000))
  (cd relay && PORT=$RELAY_PORT exec node src/node_server.js) > /tmp/net_test_relay.log 2>&1 &
  RELAY_PID=$!
  export IC_RELAY_URL="ws://127.0.0.1:$RELAY_PORT"
  sleep 1
fi
"$GODOT" --headless --path . res://tests/net_test.tscn -- host "$PORT" > /tmp/net_test_host.log 2>&1 &
HOST=$!
"$GODOT" --headless --path . res://tests/net_test.tscn -- client "$PORT" > /tmp/net_test_client.log 2>&1 &
CLIENT=$!
wait $CLIENT; CLIENT_CODE=$?
wait $HOST; HOST_CODE=$?
[ -n "$RELAY_PID" ] && kill "$RELAY_PID"
grep -h "^\[\(host\|client\)\]" /tmp/net_test_host.log /tmp/net_test_client.log
echo "host exit $HOST_CODE, client exit $CLIENT_CODE"
[ "$HOST_CODE" -eq 0 ] && [ "$CLIENT_CODE" -eq 0 ]
