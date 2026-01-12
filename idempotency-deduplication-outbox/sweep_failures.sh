#!/bin/bash
echo "=== Failure Sweep: Testing crash scenarios ==="

# Test crash after different message counts
CRASH_SCENARIOS=(1 2 3)

for CRASH_COUNT in "${CRASH_SCENARIOS[@]}"; do
    echo ""
    echo "=========================================="
    echo "Scenario: Worker crashes after $CRASH_COUNT messages"
    echo "=========================================="

    export MODE=outbox
    rm -f processed.log queue.txt outbox.db

    # Start API
    node api_server.js > /dev/null 2>&1 & API_PID=$!
    sleep 2

    # Start worker with crash simulation
    CRASH_AFTER=$CRASH_COUNT node worker.js > worker_crash_$CRASH_COUNT.log 2>&1 & WORKER_PID=$!
    sleep 1

    # Start outbox processor
    node outbox_processor.js > /dev/null 2>&1 & OUTBOX_PID=$!
    sleep 2

    # Send 5 requests
    echo "Sending 5 requests..."
    for i in {1..5}; do
        curl -s -X POST -H "Idempotency-Key: sweep-$CRASH_COUNT-$i" \
             -H "Content-Type: application/json" \
             -d '{"amount":100}' \
             http://localhost:3000/charge > /dev/null
    done

    echo "Waiting for crash and initial processing..."
    sleep 5

    # Check if worker crashed
    if ! kill -0 $WORKER_PID 2>/dev/null; then
        echo "✓ Worker crashed as expected after $CRASH_COUNT messages"

        # Restart worker without crash simulation
        echo "Restarting worker without crash simulation..."
        node worker.js > /dev/null 2>&1 & WORKER_PID=$!
        sleep 5

        # Check processed.log
        PROCESSED_COUNT=$(wc -l < processed.log 2>/dev/null || echo 0)
        echo "Processed count: $PROCESSED_COUNT"

        # Check for duplicates
        UNIQUE_COUNT=$(grep -o 'charge [0-9]*' processed.log | sort -u | wc -l 2>/dev/null || echo 0)
        echo "Unique charges: $UNIQUE_COUNT"

        if [ "$PROCESSED_COUNT" -eq "$UNIQUE_COUNT" ]; then
            echo "✓ No duplicates detected"
        else
            echo "✗ DUPLICATES FOUND! Processed: $PROCESSED_COUNT, Unique: $UNIQUE_COUNT"
        fi

        # Check outbox status
        PENDING=$(sqlite3 outbox.db "SELECT COUNT(*) FROM outbox WHERE status='pending'" 2>/dev/null || echo "N/A")
        echo "Pending outbox entries: $PENDING"

    else
        echo "✗ Worker did not crash (expected crash after $CRASH_COUNT)"
    fi

    # Cleanup
    kill $API_PID $WORKER_PID $OUTBOX_PID 2>/dev/null
    sleep 1

    echo "--- processed.log excerpt ---"
    head -n 10 processed.log 2>/dev/null || echo "(empty)"
done

echo ""
echo "=========================================="
echo "Scenario: Multiple crash/restart cycles"
echo "=========================================="

export MODE=outbox
rm -f processed.log queue.txt outbox.db

# Start API
node api_server.js > /dev/null 2>&1 & API_PID=$!
sleep 2

# Start outbox processor
node outbox_processor.js > /dev/null 2>&1 & OUTBOX_PID=$!
sleep 1

# Send 10 requests
echo "Sending 10 requests..."
for i in {1..10}; do
    curl -s -X POST -H "Idempotency-Key: multi-crash-$i" \
         -H "Content-Type: application/json" \
         -d '{"amount":100}' \
         http://localhost:3000/charge > /dev/null
done

# Start worker, let it process some, crash, restart multiple times
for cycle in {1..3}; do
    echo "Cycle $cycle: Starting worker (will crash after 2 messages)..."
    CRASH_AFTER=2 node worker.js > /dev/null 2>&1 & WORKER_PID=$!
    sleep 4

    # Worker should have crashed
    if ! kill -0 $WORKER_PID 2>/dev/null; then
        echo "✓ Worker crashed in cycle $cycle"
    fi
done

# Final run without crash
echo "Final run: Starting worker without crash simulation..."
node worker.js > /dev/null 2>&1 & WORKER_PID=$!
sleep 6

# Check results
PROCESSED_COUNT=$(wc -l < processed.log 2>/dev/null || echo 0)
UNIQUE_COUNT=$(grep -o 'charge [0-9]*' processed.log | sort -u | wc -l 2>/dev/null || echo 0)
PENDING=$(sqlite3 outbox.db "SELECT COUNT(*) FROM outbox WHERE status='pending'" 2>/dev/null || echo "N/A")

echo "Final results:"
echo "  Total processed: $PROCESSED_COUNT"
echo "  Unique charges: $UNIQUE_COUNT"
echo "  Pending outbox: $PENDING"

if [ "$PROCESSED_COUNT" -eq "$UNIQUE_COUNT" ] && [ "$PROCESSED_COUNT" -eq 10 ]; then
    echo "✓ SUCCESS: All 10 messages processed exactly once despite multiple crashes"
else
    echo "✗ ISSUE: Expected 10 unique processed, got $UNIQUE_COUNT processed, $PROCESSED_COUNT total"
fi

# Cleanup
kill $API_PID $WORKER_PID $OUTBOX_PID 2>/dev/null

echo ""
echo "=========================================="
echo "Sweep complete. Check worker_crash_*.log for crash details."
echo "=========================================="
