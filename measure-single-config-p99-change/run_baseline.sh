#!/usr/bin/env bash
export POOL_SIZE=2
export DB_CONNECTIONS=5

node db_simulator.js & DBPID=$!
sleep 0.3
node api_server.js & APIPID=$!
sleep 1

# wrk -t2 -c100 -d15s --latency http://localhost:3000/work > before.txt

wrk -t2 -c200 -d15s --latency --timeout 2s http://localhost:3000/work > before.txt

kill $APIPID $DBPID