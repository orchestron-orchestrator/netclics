# Justfile for NETCLICS API examples
# Run with: just <recipe-name>

# Default recipe
default:
    @just --list

# Start the NETCLICS server
run:
    acton run src/netclics.act

# Build the project
build:
    acton build

# Show available platforms
platforms:
    curl -s http://localhost:8080/api/v1/platforms | jq .

# Show running instances
instances:
    curl -s http://localhost:8080/api/v1/instances | jq .

# Convert NETCONF/XML to NETCONF/XML, roundtrip via crpd
test-xml-to-xml-crpd:
    #!/usr/bin/env bash
    echo "=== Conversion with before/after configs ==="
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "<configuration xmlns:junos=\"http://xml.juniper.net/junos/24.4R0/junos\"><interfaces><interface><name>eth-0/1/2</name><description>foo</description></interface></interfaces></configuration>",
        "format": "netconf",
        "target_format": "netconf",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo "Base config (before):"
    echo "$RESULT" | jq -r '.base_config' | xmllint --format -

    echo "Final config (after):"
    echo "$RESULT" | jq -r '.config' | xmllint --format -

# Test with malformed NETCONF input
test-netconf-error:
    #!/usr/bin/env bash
    curl -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "<configuration xmlns:junos=\"http://xml.juniper.net/junos/24.4R0/junos\"><interfaces><interface><name>ge-0/0/0</name><unit><name>0</name><family><inet><address><name>INVALID_IP</name></address></inet></family></unit></interface></interfaces></configuration>",
        "format": "netconf",
        "target_format": "netconf",
        "platform": "crpd 24.4R1.9-local"
      }' | jq .

# Quick test to verify server is running
ping:
    curl -s http://localhost:8080/api/v1/platforms > /dev/null && echo "✅ Server is running" || echo "❌ Server is not responding"

# Clean up build artifacts
clean:
    rm -rf out/ .acton.lock *.log
