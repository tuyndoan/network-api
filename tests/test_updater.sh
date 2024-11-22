#!/bin/bash
set -e  # Exit on any error

# Configuration
ORCHESTRATOR_HOST="beta.orchestrator.nexus.xyz"
TEST_NEW_VERSION="0.9.9"  # Define version once here

# Find project root (assuming script is in tests/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Setup cleanup trap
cleanup() {
    echo -e "\nCleaning up..."
    if [ -n "$INSTALL_PATH" ]; then  # Only if INSTALL_PATH is not empty
        # Kill any running prover processes from our test
        pkill -f "$INSTALL_PATH" || true
    fi
    # Remove test directory
    if [ -n "$TEST_DIR" ]; then      # Only if TEST_DIR is not empty
        rm -rf "$TEST_DIR"
    fi
    # Return to original directory
    cd "$PROJECT_ROOT"
    echo "Cleanup complete"
    exit 0
}

# Trap cleanup on script exit, interrupts (Ctrl+C), and termination
trap cleanup EXIT
trap cleanup INT
trap cleanup TERM

# Create clean test directory
TEST_DIR=$(mktemp -d)
echo "Setting up test in $TEST_DIR"

# Copy necessary files to test directory
cd $TEST_DIR
git clone $PROJECT_ROOT .
git checkout 0.3.5  # Safe to do in the clone

# Build and start CLI
cd clients/cli
cargo build --release
INSTALL_PATH="$TEST_DIR/clients/cli/target/release/prover"

# Start CLI and store its PID and its starting commit
echo "Starting CLI v1.0..."
STARTING_COMMIT=$(git rev-parse HEAD)  # Store the commit where we start
$INSTALL_PATH $ORCHESTRATOR_HOST &
ORIGINAL_PID=$!
echo "Original PID: $ORIGINAL_PID"


# Give CLI time to start the proving from prover.rs
sleep 30 

# Create new version with higher number than 0.3.5
echo "updated" > test.txt
git add test.txt
git commit -m "Update"
git tag $TEST_NEW_VERSION # Use a version higher than current

# If the version is not updated from v1.0 to v2.0, the test fails
if [ "$CURRENT_VERSION" != "$TEST_NEW_VERSION" ]; then
    echo "❌ Version did not update after 60 seconds"
    echo "Current version: $CURRENT_VERSION"
    echo "Expected version: $TEST_NEW_VERSION"
    exit 1
fi

# Verify that the new version is running in a new process (e.g. CLI restarted)
NEW_PID=$(pgrep -f "$INSTALL_PATH" || echo "")
echo "New PID: $NEW_PID"

# if the new PID is empty, the CLI is not running
if [ -z "$NEW_PID" ]; then
    echo "❌ CLI is not running!"
    exit 1
fi

# If the new PID is the same as the original PID, the CLI was not restarted (same process)
if [ "$NEW_PID" == "$ORIGINAL_PID" ]; then
    echo "❌ CLI was not restarted (PID unchanged)"
    echo "Original version: $(git describe --tags $STARTING_COMMIT)"  # Check version at start
    echo "Expected version: $TEST_NEW_VERSION"
    exit 1
fi

echo "✅ CLI auto-updated and restarted successfully"