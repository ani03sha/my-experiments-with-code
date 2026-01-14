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

# Clear previous traces
> traces.ndjson

echo "Running high load test..."
echo "Note: -c400 creates connection queueing which amplifies tail latency"
wrk -t8 -c400 -d60s --latency http://localhost:3000/work > high_load.txt

echo "High load results:"
cat high_load.txt | grep -A 3 "Latency"
cat high_load.txt | grep "Requests/sec"

echo "Analyzing traces..."
node trace_summary.js traces.ndjson 5 > trace_summary.txt

echo "Top slow trace:"
head -20 trace_summary.txt

echo "Stopping services..."
kill $SERVICE_A_PID $SERVICE_B_PID $SERVICE_C_PID $COLLECTOR_PID
sleep 1

cp traces.ndjson traces_high_load.ndjson

echo "High load complete. See high_load.txt and trace_summary.txt"