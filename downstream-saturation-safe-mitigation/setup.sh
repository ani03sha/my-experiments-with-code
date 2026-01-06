#!/bin/bash
# Setup script for Express version
set -e

echo "=== Setting up Queueing Demo ==="

# Create directory structure
mkdir -p {logs,results,scripts}

# Check for Node.js
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed"
    exit 1
fi

# Check for wrk
if ! command -v wrk &> /dev/null; then
    echo "Warning: wrk is not installed. Install with:"
    echo "  macOS: brew install wrk"
    echo "  Ubuntu: sudo apt-get install wrk"
    echo "  Or build from: https://github.com/wg/wrk"
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
npm init -y
npm install express node-fetch

# Make scripts executable
chmod +x *.sh

echo ""
echo "=== Setup complete ==="
echo ""
echo "Available experiments:"
echo "1. ./run_baseline.sh    - API bottleneck (small pool)"
echo "2. ./run_increase_pool.sh - Match pool to DB capacity"
echo "3. ./run_saturate_db.sh   - Overwhelm downstream"
echo "4. ./run_with_cb.sh      - With circuit breaker protection"
echo ""
echo "Run an experiment and check results/ directory for outputs."