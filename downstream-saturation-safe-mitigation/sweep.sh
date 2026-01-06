#!/bin/bash
# final_sweep.sh - Clean output, no termination messages
set -e

echo "📊 Queueing Experiment Results"
echo "=============================="

pkill -f "node" 2>/dev/null >/dev/null || true
sleep 1

# Start DB
export DB_CONC=10 WORK_MS=50
node db_simulator.js >/dev/null 2>&1 &
sleep 3

echo "| Pool | RPS    | p99     | API_Q | DB_Q |"
echo "|------|--------|---------|-------|------|"

for POOL in 2 5 10 20 50; do
    # Start API
    export POOL_SIZE=$POOL
    node api_server.js >/dev/null 2>&1 &
    API_PID=$!
    sleep 2
    
    # Run wrk
    wrk -t2 -c100 -d3s --latency http://localhost:3000/work 2>&1 > /tmp/wrk.out
    
    # Parse results
    RPS=$(grep "Requests/sec:" /tmp/wrk.out | awk '{print $2}')
    P99=$(grep -A5 "Latency" /tmp/wrk.out | grep "99%" | awk '{print $2}')
    
    # Get metrics
    API_Q=$(curl -s http://localhost:3000/metrics 2>/dev/null | grep "^api_queue " | awk '{print $2}' || echo "0")
    DB_Q=$(curl -s http://localhost:5001/metrics 2>/dev/null | grep "^db_queue " | awk '{print $2}' || echo "0")
    
    # Format for markdown
    printf "| %4s | %6s | %7s | %5s | %4s |\n" \
        "$POOL" "$RPS" "$P99" "$API_Q" "$DB_Q"
    
    # Cleanup without termination messages
    kill $API_PID 2>/dev/null >/dev/null || true
    wait $API_PID 2>/dev/null || true
    sleep 1
done

pkill -f "node db_simulator.js" 2>/dev/null >/dev/null || true

echo ""
echo "✅ Experiment complete! Copy the table above for your thread."