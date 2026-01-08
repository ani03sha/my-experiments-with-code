#!/bin/bash

# Collect metrics from dispatcher, API instances, and DB simulator
# Usage: ./collect_metrics.sh [output_file]

OUTPUT_FILE=${1:-"metrics_$(date +%s).json"}
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create a JSON object to store all metrics
echo "{" > "$OUTPUT_FILE"
echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$OUTPUT_FILE"

# Collect dispatcher metrics (with timeout)
DISPATCHER_METRICS=$(curl -s --max-time 2 --connect-timeout 1 http://localhost:8080/metrics 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$DISPATCHER_METRICS" ]; then
    echo "  \"dispatcher\": $DISPATCHER_METRICS," >> "$OUTPUT_FILE"
else
    echo "  \"dispatcher\": null," >> "$OUTPUT_FILE"
fi

# Collect autoscaler metrics (if running, with timeout)
AUTOSCALER_METRICS=$(curl -s --max-time 2 --connect-timeout 1 http://localhost:8081/metrics 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$AUTOSCALER_METRICS" ]; then
    echo "  \"autoscaler\": $AUTOSCALER_METRICS," >> "$OUTPUT_FILE"
else
    echo "  \"autoscaler\": null," >> "$OUTPUT_FILE"
fi

# Collect API instance metrics (with timeout)
echo "  \"api_instances\": [" >> "$OUTPUT_FILE"
INSTANCE_COUNT=0
for PORT in {3000..3005}; do
    METRICS=$(curl -s --max-time 1 --connect-timeout 0.5 http://localhost:$PORT/metrics 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$METRICS" ]; then
        if [ $INSTANCE_COUNT -gt 0 ]; then
            echo "," >> "$OUTPUT_FILE"
        fi
        echo "    $METRICS" >> "$OUTPUT_FILE"
        INSTANCE_COUNT=$((INSTANCE_COUNT + 1))
    fi
done
echo "" >> "$OUTPUT_FILE"
echo "  ]," >> "$OUTPUT_FILE"

# Collect DB simulator metrics (if running, with timeout)
DB_METRICS=$(curl -s --max-time 1 --connect-timeout 0.5 http://localhost:3001/metrics 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$DB_METRICS" ]; then
    echo "  \"db_simulator\": $DB_METRICS" >> "$OUTPUT_FILE"
else
    echo "  \"db_simulator\": null" >> "$OUTPUT_FILE"
fi

echo "}" >> "$OUTPUT_FILE"
