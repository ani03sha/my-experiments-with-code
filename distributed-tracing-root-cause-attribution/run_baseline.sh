#!/bin/bash

echo "Starting trace collector..."
node trace_collector.js &
COLLECTOR_PID=$!

sleep 2

echo "Starting services..."
node service_c.js &
SERVICE_C_PID=$!
sleep 1

node service_b.js &
SERVICE_B_PID=$!
sleep 1

node service_a.js &
SERVICE_A_PID=$!
sleep 2

echo "Running baseline load test..."
wrk -t4 -c200 -d20s --latency http://localhost:3000/work > baseline.txt

echo "Baseline results:"
cat baseline.txt | grep -A 3 "Latency"
cat baseline.txt | grep "Requests/sec"

echo "Collecting metrics..."
curl -s http://localhost:3000/metrics > metrics_a.json
curl -s http://localhost:3001/metrics > metrics_b.json
curl -s http://localhost:3002/metrics > metrics_c.json

echo "Stopping services..."
kill $SERVICE_A_PID $SERVICE_B_PID $SERVICE_C_PID $COLLECTOR_PID
sleep 1

# Copy traces
cp traces.ndjson traces_baseline.ndjson

echo "Baseline complete. See baseline.txt and traces_baseline.ndjson"