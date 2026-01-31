#!/bin/bash
# Run all tests from all extensions

set -e  # Exit on first error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "Running CPLUS+_Ex Extension Tests"
echo "========================================="
cd "$SCRIPT_DIR/RedactedRiceExts/exts/CPLUS+_Ex"
busted

echo ""
echo "========================================="
echo "Running memhack Extension Tests"
echo "========================================="
cd "$SCRIPT_DIR/RedactedRiceExts/exts/memhack"
busted

echo ""
echo "========================================="
echo "All tests completed successfully!"
echo "========================================="
