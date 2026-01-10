#!/bin/bash
set -e

# Start DB simulator
node db_simulator.js &
DB_PID=$!

# Start API instances
PORT=8081 INSTANCE_ID=instance-1 node api_instance.js &
INSTANCE1_PID=$!
sleep 1
PORT=8082 INSTANCE_ID=instance-2 node api_instance.js &
INSTANCE2_PID=$!
sleep 1

# Start dispatcher
node dispatcher.js &
DISPATCHER_PID=$!
sleep 2

# Run wrk baseline
wrk -t4 -c200 -d20s --latency http://localhost:8080/work > baseline.txt

# Kill processes
kill $DISPATCHER_PID $INSTANCE1_PID $INSTANCE2_PID $DB_PID
wait 2>/dev/null || true