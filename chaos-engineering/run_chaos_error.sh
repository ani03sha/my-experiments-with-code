#!/bin/bash
set -e

# Start components
node db_simulator.js &
DB_PID=$!
PORT=8081 INSTANCE_ID=instance-1 node api_instance.js &
INSTANCE1_PID=$!
sleep 1
PORT=8082 INSTANCE_ID=instance-2 node api_instance.js &
INSTANCE2_PID=$!
sleep 1
node dispatcher.js &
DISPATCHER_PID=$!
sleep 2

# Start chaos controller with error schedule
cat > error_schedule.json <<EOF
[
  { "time": 10, "type": "error", "target": "http://localhost:8081", "rate": 0.5, "duration": 20000 }
]
EOF
SCHEDULE_FILE=./error_schedule.json node chaos_controller.js &
CHAOS_PID=$!
sleep 1

# Start remediator
node remediator.js &
REMEDIATOR_PID=$!
sleep 1

# Run wrk for 60 seconds
wrk -t8 -c400 -d60s --latency http://localhost:8080/work > during_error.txt

# Kill chaos and remediator
kill $CHAOS_PID $REMEDIATOR_PID
# Kill other processes
kill $DISPATCHER_PID $INSTANCE1_PID $INSTANCE2_PID $DB_PID
wait 2>/dev/null || true
