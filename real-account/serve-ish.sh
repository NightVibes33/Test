#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
echo "Starting CloudKit research harness:"
echo "  victim:   http://127.0.0.1:8000/victim.html"
echo "  attacker: http://127.0.0.1:8001/attacker.html"
busybox httpd -p 8000 -h "$HERE"
busybox httpd -p 8001 -h "$HERE"
echo "Servers started. Open the attacker URL in Safari first."
