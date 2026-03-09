#!/bin/sh

# Exit immediately if a simple command exits with a nonzero exit value
set -e

docker build -t test-aks-with-testing-application-sso-update -f docker/dockerfile .
docker compose -f docker/docker-compose.yml run --rm update
