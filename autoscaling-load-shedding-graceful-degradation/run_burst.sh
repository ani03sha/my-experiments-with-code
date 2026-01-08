#!/bin/bash

set -e

cleanup() {
    [ -n "$DISPATCHER_PID" ] && kill $DISPATCHER_PID 2>/dev/null
    wait $DISPATCHER_PID 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Baseline Burst Test (No Protection) ==="
echo ""

# Start dispatcher with high shed threshold (effectively disabled)
SHED_THRESHOLD=999 node dispatcher.js > /dev/null 2>&1 &
DISPATCHER_PID=$!
sleep 3

if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "ERROR: Dispatcher failed to start"
    exit 1
fi

# Run short burst test
wrk -t4 -c200 -d10s --latency http://localhost:8080/work > baseline_burst.txt 2>&1

# Collect metrics
./collect_metrics.sh baseline_metrics.json > /dev/null 2>&1

# Extract metrics
P50=$(grep "50%" baseline_burst.txt | awk '{print $2}')
P95=$(grep "95%" baseline_burst.txt | awk '{print $2}')
P99=$(grep "99%" baseline_burst.txt | awk '{print $2}')
RPS=$(grep "Requests/sec" baseline_burst.txt | awk '{print $2}')
QUEUE=$(cat baseline_metrics.json | jq -r '.api_instances[0].api_queue // 0')
INSTANCES=$(cat baseline_metrics.json | jq -r '.dispatcher.dispatcher_active_instances // 0')

# Output clean results
echo "╔════════════════════════════════════════════════════════╗"
echo "║            BASELINE TEST RESULTS                       ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║ Metric              │ Value                            ║"
echo "╟────────────────────┼──────────────────────────────────╢"
printf "║ %-18s │ %-32s ║\n" "Instances" "$INSTANCES"
printf "║ %-18s │ %-32s ║\n" "Queue Depth" "$QUEUE"
printf "║ %-18s │ %-32s ║\n" "p50 Latency" "$P50"
printf "║ %-18s │ %-32s ║\n" "p95 Latency" "$P95"
printf "║ %-18s │ %-32s ║\n" "p99 Latency" "$P99"
printf "║ %-18s │ %-32s ║\n" "Requests/sec" "$RPS"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Files: baseline_burst.txt, baseline_metrics.json"