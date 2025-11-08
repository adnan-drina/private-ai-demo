#!/bin/bash
# Convenience wrapper for ACME scenario batch ingestion
exec "$(dirname "$0")/run-batch-ingestion.sh" acme
