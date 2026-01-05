export POOL_SIZE=200
export DB_CONNECTIONS=5

node db_simulator.js & DBPID=$!
sleep 0.3
node api_server.js & APIPID=$!
sleep 1

wrk -t2 -c200 -d15s --latency --timeout 2s http://localhost:3000/work > after_pool_high.txt

kill $APIPID $DBPID
