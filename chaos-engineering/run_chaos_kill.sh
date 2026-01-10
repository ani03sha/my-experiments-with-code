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

# Start chaos controller with kill schedule
cat > kill_schedule.json <<EOF
[
  { "time": 10, "type": "kill", "target": "http://localhost:8081", "duration": 0 }
]
EOF

# Start remediator
node remediator.js &
REMEDIATOR_PID=$!
sleep 1

# Wait 10 seconds then kill instance 1 manually
sleep 10
echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Killing instance-1 (PID: $INSTANCE1_PID)"
kill $INSTANCE1_PID || true

# Run wrk for 60 seconds
wrk -t8 -c400 -d60s --latency http://localhost:8080/work > during_kill.txt

# Kill remediator
kill $REMEDIATOR_PID
# Kill other processes
kill $DISPATCHER_PID $INSTANCE2_PID $DB_PID 2>/dev/null || true
wait 2>/dev/null || true
