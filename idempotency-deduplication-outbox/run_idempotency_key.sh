#!/bin/bash
echo "=== Demo 2: Idempotency key deduplication ==="
export MODE=idempotent_key
rm -f processed.log queue.txt outbox.db
node api_server.js & API_PID=$!
sleep 2
node worker.js & WORKER_PID=$!
sleep 2
KEY="dedup-test-$(date +%s)"
echo "Sending 5 requests with same key: $KEY"
for i in {1..5}; do
  curl -X POST -H "Content-Type: application/json" -H "Idempotency-Key: $KEY" \
    -d '{"amount":100}' http://localhost:3000/charge
  echo ""
done
sleep 3
echo "--- processed.log (should have 1 entry) ---"
cat processed.log
echo "--- Metrics (duplicate_detected should be 4) ---"
curl -s http://localhost:3000/metrics | python3 -m json.tool
kill $API_PID $WORKER_PID 2>/dev/null