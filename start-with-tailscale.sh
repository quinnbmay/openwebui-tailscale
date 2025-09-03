#!/bin/bash
set -e

# Function to start Tailscale
start_tailscale() {
    if [ "$ENABLE_TAILSCALE" = "true" ] && [ -n "$TAILSCALE_AUTHKEY" ] && [ "$TAILSCALE_AUTHKEY" != "PLACEHOLDER_SET_IN_ADMIN_PANEL" ]; then
        echo "🔗 Starting Tailscale daemon..."
        
        # Create state directory
        mkdir -p /tmp/tailscale
        
        # Start tailscaled in the background with state in memory
        tailscaled --state=mem: --socket=/tmp/tailscale.sock &
        TAILSCALED_PID=$!
        
        # Wait a bit for tailscaled to start
        sleep 2
        
        echo "🌐 Connecting to tailnet..."
        # Connect to the tailnet using the auth key
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
    else
        echo "⚠️  Tailscale not enabled or auth key not set"
    fi
}

# Function to cleanup on exit
cleanup() {
    if [ -n "$TAILSCALED_PID" ]; then
        echo "🛑 Stopping Tailscale daemon..."
        kill "$TAILSCALED_PID" 2>/dev/null || true
    fi
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Start Tailscale if configured
start_tailscale

# Start the original OpenWebUI application
echo "🚀 Starting OpenWebUI..."
exec bash /app/backend/start.sh