#!/bin/bash
echo "=== TTL Sweep Test ==="

for ttl in 100 500 1000 2000 5000; do
    echo -e "\n=== Testing TTL: ${ttl}ms ==="
    
    node db_simulator.js &
    DB_PID=$!
    sleep 1
    
    CACHE=naive CACHE_TTL=$ttl node api_server.js &
    API_PID=$!
    sleep 2
    
    # Warm cache
    curl -s http://localhost:3000/item/test > /dev/null
    
    # Wait for expiry based on TTL
    sleep $(echo "$ttl / 1000 + 0.1" | bc)
    
    echo "Running load after TTL expiry..."
    wrk -t4 -c200 -d10s --latency http://localhost:3000/item/test 2>&1 | grep "99%"
    
    echo "Metrics:"
    curl -s http://localhost:3000/metrics | grep -E "(p99|downstream_calls)"
    
    kill $API_PID $DB_PID
    wait
    sleep 2
done