#!/bin/bash

set -e

cleanup() {
    [ -n "$DISPATCHER_PID" ] && kill $DISPATCHER_PID 2>/dev/null
    wait $DISPATCHER_PID 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Load Shedding Test (No Autoscaling) ==="
echo ""

# Start dispatcher with load shedding enabled
POOL_SIZE=4 SHED_THRESHOLD=8 DEGRADE_MODE=0 node dispatcher.js > /dev/null 2>&1 &
DISPATCHER_PID=$!
sleep 3

if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "ERROR: Dispatcher failed to start"
    exit 1
fi

# Collect before metrics
./collect_metrics.sh before_noscale.json > /dev/null 2>&1

# Run short burst test
wrk -t4 -c200 -d10s --latency http://localhost:8080/work > noscale_burst.txt 2>&1

# Collect after metrics
./collect_metrics.sh after_noscale.json > /dev/null 2>&1

# Extract metrics
P50=$(grep "50%" noscale_burst.txt | awk '{print $2}')
P95=$(grep "95%" noscale_burst.txt | awk '{print $2}')
P99=$(grep "99%" noscale_burst.txt | awk '{print $2}')
RPS=$(grep "Requests/sec" noscale_burst.txt | awk '{print $2}')

BEFORE_SHED=$(cat before_noscale.json | jq -r '.api_instances[0].api_shed_count // 0')
AFTER_SHED=$(cat after_noscale.json | jq -r '.api_instances[0].api_shed_count // 0')
SHED_COUNT=$((AFTER_SHED - BEFORE_SHED))
AFTER_P95=$(cat after_noscale.json | jq -r '.api_instances[0].p95_estimate // 0')
INSTANCES=$(cat after_noscale.json | jq -r '.dispatcher.dispatcher_active_instances // 0')

# Output clean results
echo "╔════════════════════════════════════════════════════════╗"
echo "║          LOAD SHEDDING TEST RESULTS                    ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║ Metric              │ Value                            ║"
echo "╟────────────────────┼──────────────────────────────────╢"
printf "║ %-18s │ %-32s ║\n" "Instances" "$INSTANCES"
printf "║ %-18s │ %-32s ║\n" "Requests Shed" "$SHED_COUNT"
printf "║ %-18s │ %-32s ║\n" "p50 Latency" "$P50"
printf "║ %-18s │ %-32s ║\n" "p95 Latency (wrk)" "$P95"
printf "║ %-18s │ %-32s ║\n" "p95 Latency (app)" "${AFTER_P95}ms"
printf "║ %-18s │ %-32s ║\n" "p99 Latency" "$P99"
printf "║ %-18s │ %-32s ║\n" "Requests/sec" "$RPS"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
if [ $SHED_COUNT -gt 0 ]; then
    echo "✓ Load shedding activated ($SHED_COUNT requests shed)"
else
    echo "✗ No load shedding occurred"
fi
echo ""
echo "📊 Files: noscale_burst.txt, before_noscale.json, after_noscale.json"
