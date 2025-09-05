#!/bin/bash
set -e

# Async environment loading startup script for OpenWebUI + Tailscale
# This ensures FastAPI starts immediately for Railway healthchecks while
# loading environment variables and Tailscale in the background

# Function to start Tailscale asynchronously
start_tailscale_async() {
    if [ "$ENABLE_TAILSCALE" = "true" ] && [ -n "$TAILSCALE_AUTHKEY" ] && [ "$TAILSCALE_AUTHKEY" != "PLACEHOLDER_SET_IN_ADMIN_PANEL" ]; then
        echo "🔗 Starting Tailscale daemon (async)..."
        
        # Create state directory
        mkdir -p /tmp/tailscale
        
        # Start tailscaled in the background with state in memory
        tailscaled --state=mem: --socket=/tmp/tailscale.sock &
        TAILSCALED_PID=$!
        
        # Wait a bit for tailscaled to start
        sleep 2
        
        echo "🌐 Connecting to tailnet (async)..."
        # Connect to the tailnet using the auth key (in background)
        (
            tailscale --socket=/tmp/tailscale.sock up \
                --authkey="$TAILSCALE_AUTHKEY" \
                --hostname="${TAILSCALE_HOSTNAME:-railway-openweb-frontend}" \
                --accept-routes \
                --accept-dns
            
            echo "✅ Tailscale connected successfully!"
            
            # Show current status
            tailscale --socket=/tmp/tailscale.sock status
            
            # Clean up the auth key from environment for security
            unset TAILSCALE_AUTHKEY
        ) &
        
        # Store Tailscale process IDs for cleanup
        echo $TAILSCALED_PID > /tmp/tailscaled.pid
    else
        echo "⚠️  Tailscale not enabled or auth key not set"
    fi
}

# Function to signal environment loading readiness
signal_env_ready() {
    # Create a readiness marker for environment loading
    echo "🔄 Environment loading in progress (async)..."
    
    # This can be expanded to monitor actual environment loading completion
    # For now, we signal that basic environment is ready for FastAPI startup
    touch /tmp/env_loading_started
    
    echo "✅ Basic environment ready - FastAPI can start"
}

# Function to cleanup on exit
cleanup() {
    if [ -f /tmp/tailscaled.pid ]; then
        TAILSCALED_PID=$(cat /tmp/tailscaled.pid)
        echo "🛑 Stopping Tailscale daemon..."
        kill "$TAILSCALED_PID" 2>/dev/null || true
        rm -f /tmp/tailscaled.pid
    fi
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
}

# Set up signal handlers
trap cleanup EXIT INT TERM

echo "🚀 Starting OpenWebUI with async environment loading..."

# Signal that basic environment is ready
signal_env_ready

# Start Tailscale asynchronously (non-blocking)
start_tailscale_async

# Set environment flag to indicate async loading mode
export ASYNC_ENV_LOADING=true
export ENV_LOADING_STATUS_FILE=/tmp/env_loading_started

echo "⚡ Starting FastAPI immediately for healthchecks..."

# Start the original OpenWebUI application immediately
# This allows Railway healthchecks to pass while environment loading continues
exec bash /app/backend/start.sh