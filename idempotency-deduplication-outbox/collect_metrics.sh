#!/bin/bash
echo "=== Metrics Collection: Tracking system state over time ==="

# Clean start
export MODE=outbox
rm -f processed.log queue.txt outbox.db metrics_output.csv

# Start services
echo "Starting services..."
node api_server.js > /dev/null 2>&1 & API_PID=$!
sleep 2
node worker.js > /dev/null 2>&1 & WORKER_PID=$!
sleep 1
node outbox_processor.js > /dev/null 2>&1 & OUTBOX_PID=$!
sleep 2

# CSV header
echo "timestamp,requests_received,requests_enqueued,duplicate_detected,outbox_entries,outbox_pending,outbox_sent,charges_processed,processed_log_lines" > metrics_output.csv

# Function to collect metrics
collect_metrics() {
    TIMESTAMP=$(date +%s)

    # Get API metrics
    METRICS=$(curl -s http://localhost:3000/metrics 2>/dev/null)
    REQUESTS_RECEIVED=$(echo "$METRICS" | grep -o '"requests_received":[0-9]*' | cut -d: -f2)
    REQUESTS_ENQUEUED=$(echo "$METRICS" | grep -o '"requests_enqueued":[0-9]*' | cut -d: -f2)
    DUPLICATE_DETECTED=$(echo "$METRICS" | grep -o '"duplicate_detected":[0-9]*' | cut -d: -f2)
    OUTBOX_ENTRIES=$(echo "$METRICS" | grep -o '"outbox_entries":[0-9]*' | cut -d: -f2)

    # Get DB metrics
    OUTBOX_PENDING=$(sqlite3 outbox.db "SELECT COUNT(*) FROM outbox WHERE status='pending'" 2>/dev/null || echo 0)
    OUTBOX_SENT=$(sqlite3 outbox.db "SELECT COUNT(*) FROM outbox WHERE status='sent'" 2>/dev/null || echo 0)
    CHARGES_PROCESSED=$(sqlite3 outbox.db "SELECT COUNT(*) FROM charges WHERE status='processed'" 2>/dev/null || echo 0)

    # Get processed log count
    PROCESSED_LOG_LINES=$(wc -l < processed.log 2>/dev/null || echo 0)

    # Default to 0 if empty
    REQUESTS_RECEIVED=${REQUESTS_RECEIVED:-0}
    REQUESTS_ENQUEUED=${REQUESTS_ENQUEUED:-0}
    DUPLICATE_DETECTED=${DUPLICATE_DETECTED:-0}
    OUTBOX_ENTRIES=${OUTBOX_ENTRIES:-0}

    echo "$TIMESTAMP,$REQUESTS_RECEIVED,$REQUESTS_ENQUEUED,$DUPLICATE_DETECTED,$OUTBOX_ENTRIES,$OUTBOX_PENDING,$OUTBOX_SENT,$CHARGES_PROCESSED,$PROCESSED_LOG_LINES" >> metrics_output.csv
}

echo "Collecting baseline metrics..."
collect_metrics

echo ""
echo "Sending 10 requests (with some duplicates)..."
for i in {1..10}; do
    # Use same key for requests 3, 6, 9 to simulate retries
    if [ $i -eq 3 ] || [ $i -eq 6 ] || [ $i -eq 9 ]; then
        KEY="duplicate-key"
    else
        KEY="unique-key-$i"
    fi

    curl -s -X POST -H "Idempotency-Key: $KEY" \
         -H "Content-Type: application/json" \
         -d '{"amount":100}' \
         http://localhost:3000/charge > /dev/null

    echo "Sent request $i (key: $KEY)"

    # Collect metrics every 2 requests
    if [ $((i % 2)) -eq 0 ]; then
        sleep 1
        collect_metrics
    fi
done

echo ""
echo "Waiting for processing to complete..."
sleep 5
collect_metrics

sleep 3
collect_metrics

echo ""
echo "=== Metrics Collection Complete ==="
echo ""
echo "CSV Output (metrics_output.csv):"
cat metrics_output.csv

echo ""
echo "=== Summary ==="
FINAL_REQUESTS=$(tail -n 1 metrics_output.csv | cut -d, -f2)
FINAL_DUPLICATES=$(tail -n 1 metrics_output.csv | cut -d, -f4)
FINAL_PENDING=$(tail -n 1 metrics_output.csv | cut -d, -f6)
FINAL_PROCESSED=$(tail -n 1 metrics_output.csv | cut -d, -f8)

echo "Total requests received: $FINAL_REQUESTS"
echo "Duplicates detected: $FINAL_DUPLICATES"
echo "Pending outbox: $FINAL_PENDING"
echo "Charges processed: $FINAL_PROCESSED"
echo "Expected unique charges: $((FINAL_REQUESTS - FINAL_DUPLICATES))"

if [ "$FINAL_PROCESSED" -eq $((FINAL_REQUESTS - FINAL_DUPLICATES)) ]; then
    echo "✓ Processed count matches expected (requests - duplicates)"
else
    echo "⚠ Processed count mismatch"
fi

if [ "$FINAL_PENDING" -eq 0 ]; then
    echo "✓ All outbox entries processed"
else
    echo "⚠ $FINAL_PENDING outbox entries still pending"
fi

# Cleanup
kill $API_PID $WORKER_PID $OUTBOX_PID 2>/dev/null

echo ""
echo "Detailed CSV output saved to: metrics_output.csv"
echo "Paste for analysis:"
echo ""
echo "cat metrics_output.csv"
