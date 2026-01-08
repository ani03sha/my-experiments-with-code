#!/bin/bash

# Autoscaler wrapper script
# This script starts the Node.js autoscaler with configurable parameters

# Configuration via environment variables
SCALE_UP_THRESHOLD=${SCALE_UP_THRESHOLD:-100}
SCALE_DOWN_THRESHOLD=${SCALE_DOWN_THRESHOLD:-30}
SCALE_UP_TIME=${SCALE_UP_TIME:-5000}
SCALE_DOWN_TIME=${SCALE_DOWN_TIME:-30000}
MIN_INSTANCES=${MIN_INSTANCES:-1}
MAX_INSTANCES=${MAX_INSTANCES:-5}

echo "Starting autoscaler with configuration:"
echo "  Scale up if p95 > ${SCALE_UP_THRESHOLD}ms for ${SCALE_UP_TIME}ms"
echo "  Scale down if p95 < ${SCALE_DOWN_THRESHOLD}ms for ${SCALE_DOWN_TIME}ms"
echo "  Instance range: ${MIN_INSTANCES} to ${MAX_INSTANCES}"
echo ""

# Start the Node.js autoscaler
node autoscaler.js
