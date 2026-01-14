#!/bin/bash

echo "Collecting metrics from all services..."
echo "Timestamp: $(date)"

echo -e "\n=== Service A Metrics ==="
curl -s http://localhost:3000/metrics | jq .

echo -e "\n=== Service B Metrics ==="
curl -s http://localhost:3001/metrics | jq .

echo -e "\n=== Service C Metrics ==="
curl -s http://localhost:3002/metrics | jq .

echo -e "\n=== Trace Count ==="
wc -l traces.ndjson 2>/dev/null || echo "No traces file"