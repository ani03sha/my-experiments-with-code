#!/bin/bash
echo "=== Demo 1: Naive at-least-once (shows duplicates) ==="
export MODE=naive
rm -f processed.log queue.txt outbox.db
node api_server.js & API_PID=$!
sleep 2
node worker.js & WORKER_PID=$!
sleep 2
echo "Sending same request 5 times (simulating retries)..."
for i in {1..5}; do
  curl -X POST -H "Content-Type: application/json" \
    -d '{"amount":100}' http://localhost:3000/charge
  echo ""
done
sleep 3
echo "--- processed.log contents ---"
cat processed.log
kill $API_PID $WORKER_PID 2>/dev/null