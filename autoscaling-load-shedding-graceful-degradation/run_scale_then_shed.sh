#!/bin/bash

set -e

cleanup() {
    [ -n "$DISPATCHER_PID" ] && kill $DISPATCHER_PID 2>/dev/null
    [ -n "$AUTOSCALER_PID" ] && kill $AUTOSCALER_PID 2>/dev/null
    wait $DISPATCHER_PID 2>/dev/null || true
    wait $AUTOSCALER_PID 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Combined: Autoscaling + Load Shedding Test ==="
echo ""

# Start dispatcher with load shedding
POOL_SIZE=4 SHED_THRESHOLD=8 DEGRADE_MODE=0 node dispatcher.js > /dev/null 2>&1 &
DISPATCHER_PID=$!
sleep 3

# Start autoscaler
node autoscaler.js > /dev/null 2>&1 &
AUTOSCALER_PID=$!
sleep 3

if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "ERROR: Services failed to start"
    exit 1
fi

# Collect before metrics
./collect_metrics.sh before_combined.json > /dev/null 2>&1

# Run burst test (reduced time)
echo "Triggering autoscaling with burst traffic..."
wrk -t4 -c200 -d12s --latency http://localhost:8080/work > combined_burst.txt 2>&1 &
WRK_PID=$!

# Monitor scaling
sleep 6
MID_INSTANCES=$(curl -s http://localhost:8080/metrics 2>/dev/null | grep -o '"dispatcher_active_instances":[0-9]*' | cut -d':' -f2 || echo "1")
echo "  Instances after 6s: $MID_INSTANCES"

wait $WRK_PID

# Wait for stabilization
sleep 5

# Collect after metrics
./collect_metrics.sh after_combined.json > /dev/null 2>&1

# Extract metrics
P50=$(grep "50%" combined_burst.txt | awk '{print $2}')
P95=$(grep "95%" combined_burst.txt | awk '{print $2}')
P99=$(grep "99%" combined_burst.txt | awk '{print $2}')
RPS=$(grep "Requests/sec" combined_burst.txt | awk '{print $2}')

BEFORE_INSTANCES=$(cat before_combined.json | jq -r '.dispatcher.dispatcher_active_instances // 1')
AFTER_INSTANCES=$(cat after_combined.json | jq -r '.dispatcher.dispatcher_active_instances // 1')
TOTAL_SHED=$(cat after_combined.json | jq -r '[.api_instances[].api_shed_count] | add // 0')
BEFORE_P95=$(cat before_combined.json | jq -r '.dispatcher.p95_estimate // 0')
AFTER_P95=$(cat after_combined.json | jq -r '.dispatcher.p95_estimate // 0')
SCALE_EVENTS=$(cat after_combined.json | jq -r '.autoscaler.scale_history | length // 0')

# Output clean results
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║       COMBINED AUTOSCALING + SHEDDING RESULTS         ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║ Metric              │ Value                            ║"
echo "╟────────────────────┼──────────────────────────────────╢"
printf "║ %-18s │ %-32s ║\n" "Initial Instances" "$BEFORE_INSTANCES"
printf "║ %-18s │ %-32s ║\n" "Final Instances" "$AFTER_INSTANCES"
printf "║ %-18s │ %-32s ║\n" "Scaled By" "$((AFTER_INSTANCES - BEFORE_INSTANCES))"
printf "║ %-18s │ %-32s ║\n" "Scale Events" "$SCALE_EVENTS"
printf "║ %-18s │ %-32s ║\n" "Total Requests Shed" "$TOTAL_SHED"
printf "║ %-18s │ %-32s ║\n" "p50 Latency" "$P50"
printf "║ %-18s │ %-32s ║\n" "p95 Latency" "$P95"
printf "║ %-18s │ %-32s ║\n" "p99 Latency" "$P99"
printf "║ %-18s │ %-32s ║\n" "Requests/sec" "$RPS"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
if [ $((AFTER_INSTANCES - BEFORE_INSTANCES)) -gt 0 ]; then
    echo "✓ Autoscaling worked (added $((AFTER_INSTANCES - BEFORE_INSTANCES)) instances)"
fi
if [ $TOTAL_SHED -gt 0 ]; then
    echo "✓ Load shedding protected during scale-up ($TOTAL_SHED shed)"
fi
echo ""
echo "📊 Files: combined_burst.txt, before_combined.json, after_combined.json"
