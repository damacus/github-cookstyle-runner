#!/bin/bash
# Script to run tests in a Docker container with isolated environment
set -e

echo "Building test Docker image..."
docker compose -f docker-compose.test.yml build

echo "Running tests in Docker container..."
docker compose -f docker-compose.test.yml run --rm test

echo "Tests completed."
