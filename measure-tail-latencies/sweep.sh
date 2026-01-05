for p in 2 5 10 20 50; do
  for d in 2 5 10; do
    echo "POOL=$p DB_CONNECTIONS=$d"
    export POOL_SIZE=$p; export DB_CONNECTIONS=$d
    node db_simulator.js & DBPID=$!
    sleep 0.5
    node api_server.js & APIPID=$!
    sleep 0.5
    wrk -t2 -c100 -d15s --latency http://localhost:3000/work > out.p${p}.d${d}.txt
    kill $APIPID $DBPID
    sleep 0.2
  done
done