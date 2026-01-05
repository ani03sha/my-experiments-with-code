export POOL_SIZE=20
export DB_CONNECTIONS=5
export CB=1
export CB_THRESHOLD=10
node db_simulator.js & DBPID=$!
sleep 0.5
node api_server.js & APIPID=$!
sleep 1
wrk -t2 -c100 -d15s --latency http://localhost:3000/work > after_cb.txt
kill $APIPID $DBPID