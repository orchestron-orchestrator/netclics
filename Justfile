# Justfile for NETCLICS API examples
# Run with: just <recipe-name>

# Default recipe
default:
    @just --list

# Start the NETCLICS server
run:
    out/bin/netclics

# Build the project
build:
    acton build

build-ldep:
    acton build --dep yang=../acton-yang --dep netconf=../netconf --dep netcli=../netcli

IMAGE_PATH := env_var_or_default("IMAGE_PATH", "ghcr.io/orchestron-orchestrator/")

start-static-instances:
    docker run -d --name crpd1 --rm --privileged --publish 42830:830 --publish 42022:22 -v ./test/crpd-startup.conf:/juniper.conf -v ./router-licenses/juniper_crpd24.lic:/config/license/juniper_crpd24.lic {{IMAGE_PATH}}crpd:24.4R1.9
    docker exec crpd1 cli -c "configure private; load merge /juniper.conf; commit"

stop-static-instances:
    docker stop crpd1

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

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

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

# Test CLI input with set commands
test-cli-to-netconf:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "set interfaces ge-0/0/1 description \"CLI test interface\"\nset interfaces ge-0/0/1 unit 0 family inet address 10.1.1.1/24",
        "format": "cli",
        "target_format": "netconf",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test NETCONF to CLI conversion
test-netconf-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "<configuration xmlns:junos=\"http://xml.juniper.net/junos/24.4R0/junos\"><interfaces><interface><name>ge-0/0/2</name><description>XML test interface</description><unit><name>0</name><family><inet><address><name>10.2.2.1/24</name></address></inet></family></unit></interface></interfaces></configuration>",
        "format": "netconf",
        "target_format": "cli",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test CLI to CLI roundtrip (should normalize configuration)
test-cli-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "set interfaces ge-0/0/3 description \"CLI roundtrip test\"\nset interfaces ge-0/0/3 unit 0 family inet address 10.3.3.1/24",
        "format": "cli",
        "target_format": "cli",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test CLI to Acton adata conversion
test-cli-to-acton-adata:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "set interfaces ge-0/0/4 description \"CLI to adata test\"\nset interfaces ge-0/0/4 unit 0 family inet address 10.4.4.1/24",
        "format": "cli",
        "target_format": "acton-adata",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test CLI to Acton gdata conversion
test-cli-to-acton-gdata:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "set interfaces ge-0/0/5 description \"CLI to gdata test\"\nset interfaces ge-0/0/5 unit 0 family inet address 10.5.5.1/24",
        "format": "cli",
        "target_format": "acton-gdata",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test CLI to JSON conversion
test-cli-to-json:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "set interfaces ge-0/0/6 description \"CLI to JSON test\"\nset interfaces ge-0/0/6 unit 0 family inet address 10.6.6.1/24",
        "format": "cli",
        "target_format": "json",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff' | jq .

# MCP: Initialize connection
test-mcp-initialize:
    #!/usr/bin/env bash
    echo "=== MCP Initialize ==="
    curl -s -X POST http://localhost:8080/mcp \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
          "protocolVersion": "2025-06-18",
          "capabilities": {},
          "clientInfo": {
            "name": "test-client",
            "version": "1.0.0"
          }
        }
      }' | jq .

# MCP: List available tools
test-mcp-tools-list:
    #!/usr/bin/env bash
    echo "=== MCP Tools List ==="
    curl -s -X POST http://localhost:8080/mcp \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list",
        "params": {}
      }' | jq .

# MCP: Call convert_config tool
test-mcp-convert:
    #!/usr/bin/env bash
    echo "=== MCP Convert Config Tool ==="
    curl -s -X POST http://localhost:8080/mcp \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
          "name": "convert_config",
          "arguments": {
            "input_config": "set interfaces ge-0/0/7 description \"MCP test interface\"\nset interfaces ge-0/0/7 unit 0 family inet address 10.7.7.1/24",
            "format": "cli",
            "target_format": "netconf",
            "platform": "crpd 24.4R1.9-local"
          }
        }
      }' | jq .

# MCP: Call list_platforms tool
test-mcp-platforms:
    #!/usr/bin/env bash
    echo "=== MCP List Platforms Tool ==="
    curl -s -X POST http://localhost:8080/mcp \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {
          "name": "list_platforms",
          "arguments": {}
        }
      }' | jq .

# MCP: Call list_instances tool
test-mcp-instances:
    #!/usr/bin/env bash
    echo "=== MCP List Instances Tool ==="
    curl -s -X POST http://localhost:8080/mcp \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "id": 5,
        "method": "tools/call",
        "params": {
          "name": "list_instances",
          "arguments": {}
        }
      }' | jq .

# MCP: Test all endpoints
test-mcp-all: test-mcp-initialize test-mcp-tools-list test-mcp-platforms test-mcp-instances test-mcp-convert

# Test IOS XRd CLI to Acton adata conversion
test-iosxrd-cli-to-acton-adata:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "interface GigabitEthernet0/0/0/1\n description \"IOS XRd test interface\"\n ipv4 address 10.1.1.1 255.255.255.0\n no shutdown",
        "format": "cli",
        "target_format": "acton-adata",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test IOS XRd CLI to CLI roundtrip
test-iosxrd-cli-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "interface GigabitEthernet0/0/0/2\n description \"IOS XRd CLI roundtrip\"\n ipv4 address 10.2.2.1 255.255.255.0\n no shutdown",
        "format": "cli",
        "target_format": "cli",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test IOS XRd NETCONF to CLI conversion
test-iosxrd-netconf-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "<configuration><interfaces xmlns=\"http://openconfig.net/yang/interfaces\"><interface><name>GigabitEthernet0/0/0/3</name><config><name>GigabitEthernet0/0/0/3</name><description>IOS XRd NETCONF test</description></config></interface></interfaces></configuration>",
        "format": "netconf",
        "target_format": "cli",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test IOS XRd CLI to NETCONF conversion
test-iosxrd-cli-to-netconf:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "interface GigabitEthernet0/0/0/4\n description \"IOS XRd to NETCONF\"\n ipv4 address 10.4.4.1 255.255.255.0\n no shutdown",
        "format": "cli",
        "target_format": "netconf",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff'

# Test IOS XRd CLI to JSON conversion
test-iosxrd-cli-to-json:
    #!/usr/bin/env bash
    RESULT=$(curl -s -X POST http://localhost:8080/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": "interface GigabitEthernet0/0/0/5\n description \"IOS XRd to JSON\"\n ipv4 address 10.5.5.1 255.255.255.0\n no shutdown",
        "format": "cli",
        "target_format": "json",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.diff' | jq .

# Run all IOS XRd tests
test-iosxrd-all: test-iosxrd-cli-to-acton-adata test-iosxrd-cli-to-cli test-iosxrd-netconf-to-cli test-iosxrd-cli-to-netconf test-iosxrd-cli-to-json

# Clean up build artifacts
clean:
    rm -rf out/ .acton.lock *.log
