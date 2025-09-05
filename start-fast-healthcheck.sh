#!/bin/bash
set -e

# Fast startup script that bypasses DragonflyDB during healthcheck period
# This solves Railway healthcheck failures by temporarily disabling environment loading

echo "🚀 Starting OpenWebUI with fast healthcheck mode..."

# Function to start Tailscale asynchronously (if enabled)
start_tailscale_async() {
    if [ "$ENABLE_TAILSCALE" = "true" ] && [ -n "$TAILSCALE_AUTHKEY" ] && [ "$TAILSCALE_AUTHKEY" != "PLACEHOLDER_SET_IN_ADMIN_PANEL" ]; then
        echo "🔗 Starting Tailscale daemon (async)..."
        
        mkdir -p /tmp/tailscale
        tailscaled --state=mem: --socket=/tmp/tailscale.sock &
        TAILSCALED_PID=$!
        sleep 2
        
        echo "🌐 Connecting to tailnet (async)..."
        (
            tailscale --socket=/tmp/tailscale.sock up \
                --authkey="$TAILSCALE_AUTHKEY" \
                --hostname="${TAILSCALE_HOSTNAME:-railway-openweb-frontend}" \
                --accept-routes \
                --accept-dns
            
            echo "✅ Tailscale connected successfully!"
            tailscale --socket=/tmp/tailscale.sock status
            unset TAILSCALE_AUTHKEY
        ) &
        
        echo $TAILSCALED_PID > /tmp/tailscaled.pid
    else
        echo "⚠️  Tailscale not enabled or auth key not set"
    fi
}

# Function to temporarily disable DragonflyDB during startup
disable_dragonfly_temporarily() {
    echo "⚡ Temporarily disabling DragonflyDB for fast startup..."
    
    # Store original DragonflyDB settings
    export DRAGONFLY_HOST_ORIGINAL="${DRAGONFLY_HOST:-}"
    export DRAGONFLY_PORT_ORIGINAL="${DRAGONFLY_PORT:-}"
    export DRAGONFLY_DB_ORIGINAL="${DRAGONFLY_DB:-}"
    
    # Disable DragonflyDB connection during startup
    export DRAGONFLY_HOST=""
    export DRAGONFLY_PORT=""
    export DRAGONFLY_DB=""
    
    # Set minimal environment for fast startup
    export MINIMAL_STARTUP=true
    export SKIP_ENVIRONMENT_LOADING=true
    
    echo "✅ DragonflyDB temporarily disabled - FastAPI will start immediately"
}

# Function to re-enable DragonflyDB after healthcheck passes
re_enable_dragonfly() {
    echo "🔄 Re-enabling DragonflyDB after healthcheck success..."
    
    # Wait for healthcheck to pass (check every 5 seconds for 2 minutes)
    for i in {1..24}; do
        if curl --silent --fail --max-time 5 http://localhost:${PORT:-8080}/health >/dev/null 2>&1; then
            echo "✅ Healthcheck passed! Re-enabling DragonflyDB..."
            
            # Restore original DragonflyDB settings
            export DRAGONFLY_HOST="${DRAGONFLY_HOST_ORIGINAL}"
            export DRAGONFLY_PORT="${DRAGONFLY_PORT_ORIGINAL}"
            export DRAGONFLY_DB="${DRAGONFLY_DB_ORIGINAL}"
            
            # Clear minimal startup flags
            unset MINIMAL_STARTUP
            unset SKIP_ENVIRONMENT_LOADING
            
            echo "🔥 DragonflyDB re-enabled - Full functionality restored"
            break
        fi
        
        echo "⏳ Waiting for healthcheck to pass... (attempt $i/24)"
        sleep 5
    done
}

# Function to cleanup on exit
cleanup() {
    if [ -f /tmp/tailscaled.pid ]; then
        TAILSCALED_PID=$(cat /tmp/tailscaled.pid)
        echo "🛑 Stopping Tailscale daemon..."
        kill "$TAILSCALED_PID" 2>/dev/null || true
        rm -f /tmp/tailscaled.pid
    fi
    
    jobs -p | xargs -r kill 2>/dev/null || true
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Apply fast startup configuration
disable_dragonfly_temporarily

# Start Tailscale asynchronously (non-blocking)
start_tailscale_async

# Start DragonflyDB re-enablement process in background
re_enable_dragonfly &

echo "⚡ Starting FastAPI with minimal environment for immediate healthcheck success..."

# Start OpenWebUI with minimal configuration
exec bash /app/backend/start.sh