#!/bin/bash
# Sample metrics endpoints at intervals
for i in {1..5}; do
    curl -s http://localhost:8080/metrics >> metrics_dispatcher.txt
    curl -s http://localhost:8081/metrics >> metrics_instance1.txt
    curl -s http://localhost:8082/metrics >> metrics_instance2.txt
    sleep 5
done