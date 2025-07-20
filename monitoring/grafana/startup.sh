#!/bin/bash

# Start Grafana in the background
/run.sh &

# Wait for Grafana to become ready
echo "Waiting for Grafana to become ready..."
until curl -s http://localhost:3000/api/health | grep -q '"database":true'; do
  sleep 2
done

echo "Grafana is ready. Creating user..."
/etc/grafana/create-viewer.sh

# Wait for background Grafana process to keep container running
wait
