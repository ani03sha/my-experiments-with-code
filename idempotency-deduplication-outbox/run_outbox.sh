#!/bin/bash
echo "=== Demo 3: Transactional outbox with worker crash ==="
export MODE=outbox
rm -f processed.log queue.txt outbox.db
node api_server.js & API_PID=$!
sleep 2
CRASH_AFTER=2 node worker.js & WORKER_PID=$!
sleep 1
node outbox_processor.js & OUTBOX_PID=$!
sleep 2
KEY="outbox-test-$(date +%s)"
echo "Sending 3 requests with outbox pattern..."
for i in {1..3}; do
  curl -X POST -H "Idempotency-Key: $KEY-$i" -H "Content-Type: application/json" \
    -d '{"amount":100}' http://localhost:3000/charge
  echo ""
done
echo "Waiting for crash..."
sleep 5
echo "Worker crashed. Restarting worker without crash simulation..."
node worker.js & WORKER_PID=$!
sleep 5
echo "--- processed.log (all 3 processed despite crash) ---"
cat processed.log
echo "--- Outbox status (should be 0 pending) ---"
sqlite3 outbox.db "SELECT COUNT(*) as pending_outbox FROM outbox WHERE status='pending'"
echo "--- Charges status ---"
sqlite3 outbox.db "SELECT id, amount, status FROM charges"
kill $API_PID $WORKER_PID $OUTBOX_PID 2>/dev/null