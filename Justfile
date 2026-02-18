# Justfile for NETCLICS API examples
# Run with: just <recipe-name>

# Default recipe
default:
    @just --list

# Start the NETCLICS server
run:
    out/bin/netclics

# Start NETCLICS with both HTTP and HTTPS endpoints
# Example:
#   just run-https TLS_CERT=./certs/server.crt TLS_KEY=./certs/server.key HTTPS_PORT=8443
run-https TLS_CERT='certs/server.crt' TLS_KEY='certs/server.key' HTTPS_PORT='8443' HTTP_PORT='8080':
    out/bin/netclics --port {{HTTP_PORT}} --https-port {{HTTPS_PORT}} --tls-cert {{TLS_CERT}} --tls-key {{TLS_KEY}}

# Build the project
build:
    acton build

build-ldep:
    acton build --dep yang=../acton-yang --dep netconf=../netconf --dep netcli=../netcli

IMAGE_PATH := env_var_or_default("IMAGE_PATH", "ghcr.io/orchestron-orchestrator/")
# Base URL used by API/MCP test recipes.
# Defaults to HTTP on 8080, override for HTTPS:
#   NETCLICS_BASE_URL=https://localhost:8443 just test-cli-to-netconf
NETCLICS_BASE_URL := env_var_or_default("NETCLICS_BASE_URL", "http://localhost:8080")
# Extra curl options used by API/MCP test recipes.
# Default includes -k for self-signed HTTPS certificates.
NETCLICS_CURL_OPTS := env_var_or_default("NETCLICS_CURL_OPTS", "-k")

start-static-instances-crpd:
    docker run -td --name crpd1 --rm --privileged --publish 42830:830 --publish 42022:22 -v ./test/crpd-startup.conf:/juniper.conf -v ./router-licenses/juniper_crpd24.lic:/config/license/juniper_crpd24.lic {{IMAGE_PATH}}crpd:24.4R1.9
    docker exec crpd1 cli -c "configure private; load merge /juniper.conf; commit"

start-static-instances-xrd:
    #!/usr/bin/env bash
    set -e
    # Build XR_INTERFACES environment variable with GigabitEthernet interfaces
    # Format: Gi0/0/0/port - XRd only supports 0/0/0/<port> format
    XR_INTERFACES=""
    for port in {0..23}; do
        if [ -n "$XR_INTERFACES" ]; then
            XR_INTERFACES="${XR_INTERFACES};"
        fi
        XR_INTERFACES="${XR_INTERFACES}linux:Gi0-0-0-${port},xr_name=Gi0/0/0/${port}"
    done

    # Start XRd container with all interface mappings to dummy Gi0/0/0/X interfaces
    # We use the snoop* flags to indicate that IPv4/IPv6 management interface
    # settings should be snooped from the eth0 (container) interface:
    # https://xrdocs.io/virtual-routing/tutorials/2022-08-25-user-interface-and-knobs-for-xrd/
    docker run -td --name xrd1 --rm --privileged \
        --publish 43830:830 --publish 43022:22 \
        -v ./test/xrd-startup.conf:/etc/xrd/first-boot.cfg \
        --env XR_FIRST_BOOT_CONFIG=/etc/xrd/first-boot.cfg \
        --env XR_MGMT_INTERFACES="linux:eth0,xr_name=Mg0/RP0/CPU0/0,chksum,snoop_v4,snoop_v4_default_route,snoop_v6,snoop_v6_default_route" \
        --env XR_INTERFACES="$XR_INTERFACES" \
        {{IMAGE_PATH}}ios-xr/xrd-control-plane:24.1.1

    sleep 1
    # Create GigabitEthernet dummy interfaces (48 ports on slot 0)
    for port in {0..23}; do
        docker exec xrd1 ip link add Gi0-0-0-${port} type dummy
    done

    docker run -td --name xrd2 --rm --privileged \
        --publish 45830:830 --publish 45022:22 \
        -v ./test/xrd-startup.conf:/etc/xrd/first-boot.cfg \
        --env XR_FIRST_BOOT_CONFIG=/etc/xrd/first-boot.cfg \
        --env XR_MGMT_INTERFACES="linux:eth0,xr_name=Mg0/RP0/CPU0/0,chksum,snoop_v4,snoop_v4_default_route,snoop_v6,snoop_v6_default_route" \
        --env XR_INTERFACES="$XR_INTERFACES" \
        {{IMAGE_PATH}}ios-xr/xrd-control-plane:25.3.1

    sleep 1
    # Create GigabitEthernet dummy interfaces (48 ports on slot 0)
    for port in {0..23}; do
        docker exec xrd2 ip link add Gi0-0-0-${port} type dummy
    done

start-static-instances-xe:
    docker run -td --name xe1 --rm --privileged --publish 44830:830 --publish 44022:22 {{IMAGE_PATH}}vrnetlab/vr-c8000v:17.18.02 --trace

# Start all static instances
start-static-instances: start-static-instances-crpd start-static-instances-xrd start-static-instances-xe

stop-static-instances:
    docker stop crpd1 xrd1 xrd2 xe1 || true

# Show available platforms
platforms:
    curl {{NETCLICS_CURL_OPTS}} -s {{NETCLICS_BASE_URL}}/api/v1/platforms | jq .

# Show running instances
instances:
    curl {{NETCLICS_CURL_OPTS}} -s {{NETCLICS_BASE_URL}}/api/v1/instances | jq .

# Convert NETCONF/XML to NETCONF/XML, roundtrip via crpd
test-xml-to-xml-crpd:
    #!/usr/bin/env bash
    echo "=== Conversion with before/after configs ==="
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["<configuration xmlns:junos=\"http://xml.juniper.net/junos/24.4R0/junos\"><interfaces><interface><name>eth-0/1/2</name><description>XML to XML test</description><unit><name>0</name><family><inet><address><name>10.1.1.1/24</name></address></inet></family></unit></interface></interfaces></configuration>"],
        "format": "netconf",
        "target_format": "netconf",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test with malformed NETCONF input
test-netconf-error:
    #!/usr/bin/env bash
    curl {{NETCLICS_CURL_OPTS}} -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["<configuration xmlns:junos=\"http://xml.juniper.net/junos/24.4R0/junos\"><interfaces><interface><name>ge-0/0/0</name><unit><name>0</name><family><inet><address><name>INVALID_IP</name></address></inet></family></unit></interface></interfaces></configuration>"],
        "format": "netconf",
        "target_format": "netconf",
        "platform": "crpd 24.4R1.9-local"
      }' | jq .

# Quick test to verify server is running
ping:
    curl {{NETCLICS_CURL_OPTS}} -s {{NETCLICS_BASE_URL}}/api/v1/platforms > /dev/null && echo "✅ Server is running" || echo "❌ Server is not responding"

# Quick HTTPS health check (self-signed cert friendly)
ping-https HTTPS_PORT='8443':
    curl -sk https://localhost:{{HTTPS_PORT}}/api/v1/platforms > /dev/null && echo "✅ HTTPS endpoint is running" || echo "❌ HTTPS endpoint is not responding"

# Test CLI input with set commands
test-cli-to-netconf:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["set interfaces ge-0/0/1 description \"CLI test interface\"", "set interfaces ge-0/0/1 unit 0 family inet address 10.1.1.1/24"],
        "format": "cli",
        "target_format": "netconf",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test NETCONF to CLI conversion
test-netconf-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["<configuration xmlns:junos=\"http://xml.juniper.net/junos/24.4R0/junos\"><interfaces><interface><name>ge-0/0/2</name><description>XML test interface</description><unit><name>0</name><family><inet><address><name>10.2.2.1/24</name></address></inet></family></unit></interface></interfaces></configuration>"],
        "format": "netconf",
        "target_format": "cli",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test CLI to CLI roundtrip (should normalize configuration)
test-cli-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["set interfaces ge-0/0/3 description \"CLI roundtrip test\"", "set interfaces ge-0/0/3 unit 0 family inet address 10.3.3.1/24"],
        "format": "cli",
        "target_format": "cli",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test CLI to Acton adata conversion
test-cli-to-acton-adata:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["set interfaces ge-0/0/4 description \"CLI to adata test\"", "set interfaces ge-0/0/4 unit 0 family inet address 10.4.4.1/24"],
        "format": "cli",
        "target_format": "acton-adata",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test CLI to Acton gdata conversion
test-cli-to-acton-gdata:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["set interfaces ge-0/0/5 description \"CLI to gdata test\"", "set interfaces ge-0/0/5 unit 0 family inet address 10.5.5.1/24"],
        "format": "cli",
        "target_format": "acton-gdata",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test CLI to JSON conversion
test-cli-to-json:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["set interfaces ge-0/0/6 description \"CLI to JSON test\"", "set interfaces ge-0/0/6 unit 0 family inet address 10.6.6.1/24"],
        "format": "cli",
        "target_format": "json",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff' | jq .

# MCP: Initialize connection
test-mcp-initialize:
    #!/usr/bin/env bash
    echo "=== MCP Initialize ==="
    curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/mcp \
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
    curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/mcp \
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
    curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/mcp \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
          "name": "convert_config",
          "arguments": {
            "input_config": ["set interfaces ge-0/0/7 description \"MCP test interface\"", "set interfaces ge-0/0/7 unit 0 family inet address 10.7.7.1/24"],
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
    curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/mcp \
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
    curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/mcp \
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
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet0/0/0/1\n description \"IOS XRd test interface\"\n ipv4 address 10.1.1.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "acton-adata",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test IOS XRd CLI to CLI roundtrip
test-iosxrd-cli-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet0/0/0/2\n description \"IOS XRd CLI roundtrip\"\n ipv4 address 10.2.2.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "cli",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test IOS XRd NETCONF to CLI conversion
test-iosxrd-netconf-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["<interfaces xmlns=\"http://cisco.com/ns/yang/Cisco-IOS-XR-um-interface-cfg\"><interface><interface-name>GigabitEthernet0/0/0/3</interface-name><description>IOS XRd NETCONF to CLI test</description><ipv4><addresses xmlns=\"http://cisco.com/ns/yang/Cisco-IOS-XR-um-if-ip-address-cfg\"><address><address>10.1.1.1</address><netmask>255.255.255.0</netmask></address></addresses></ipv4></interface></interfaces>"],
        "format": "netconf",
        "target_format": "cli",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test IOS XRd CLI to NETCONF conversion
test-iosxrd-cli-to-netconf:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet0/0/0/4\n description \"IOS XRd to NETCONF\"\n ipv4 address 10.4.4.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "netconf",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test IOS XRd CLI to JSON conversion
test-iosxrd-cli-to-json:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet0/0/0/5\n description \"IOS XRd to JSON\"\n ipv4 address 10.5.5.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "json",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff' | jq .

# Test IOS XRd CLI to Acton adata conversion with unified-model module-set
test-iosxrd-cli-to-acton-adata-unified-model:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet0/0/0/6\n description \"IOS XRd unified-model test\"\n ipv4 address 10.6.6.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "acton-adata",
        "platform": "iosxrd 24.1.1-local",
        "module_set": "cisco-xr-unified-model"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Run all IOS XRd tests
test-iosxrd-all: test-iosxrd-cli-to-acton-adata test-iosxrd-cli-to-cli test-iosxrd-netconf-to-cli test-iosxrd-cli-to-netconf test-iosxrd-cli-to-json

# Test IOS XE CLI to Acton adata conversion
test-iosxe-cli-to-acton-adata:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet2\n description \"IOS XE test interface\"\n ip address 10.1.1.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "acton-adata",
        "platform": "iosxe 17.18.02-local",
        "module_set": "cisco-xe-native"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test IOS XE CLI to CLI roundtrip
test-iosxe-cli-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet2\n description \"IOS XE CLI roundtrip\"\n ip address 10.2.2.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "cli",
        "platform": "iosxe 17.18.02-local",
        "module_set": "cisco-xe-native"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test IOS XE NETCONF to CLI conversion
test-iosxe-netconf-to-cli:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["<native xmlns=\"http://cisco.com/ns/yang/Cisco-IOS-XE-native\"><interface><GigabitEthernet><name>2</name><description>IOS XE NETCONF to CLI</description><ip><address><primary><address>10.1.1.1</address><mask>255.255.255.0</mask></primary></address></ip></GigabitEthernet></interface></native>"],
        "format": "netconf",
        "target_format": "cli",
        "platform": "iosxe 17.18.02-local",
        "module_set": "cisco-xe-native"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test IOS XE CLI to NETCONF conversion
test-iosxe-cli-to-netconf:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet2\n description \"IOS XE CLI to NETCONF\"\n ip address 10.4.4.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "netconf",
        "platform": "iosxe 17.18.02-local",
        "module_set": "cisco-xe-native"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff'

# Test IOS XE CLI to JSON conversion
test-iosxe-cli-to-json:
    #!/usr/bin/env bash
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": ["interface GigabitEthernet2\n description \"IOS XE CLI to JSON\"\n ip address 10.5.5.1 255.255.255.0\n no shutdown"],
        "format": "cli",
        "target_format": "json",
        "platform": "iosxe 17.18.02-local",
        "module_set": "cisco-xe-native"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Configuration Diff ==="
    echo "$RESULT" | jq -r '.steps[0].diff' | jq .

# Run all IOS XE tests
test-iosxe-all: test-iosxe-cli-to-acton-adata test-iosxe-cli-to-cli test-iosxe-netconf-to-cli test-iosxe-cli-to-netconf test-iosxe-cli-to-json

# Wait for all instances to be ready (reach "ready" state)
# Usage: just wait-for-instances [timeout_seconds]
# Default timeout: 180 seconds
wait-for-instances timeout="180":
    #!/usr/bin/env bash
    echo "Waiting for all instances to be ready..."

    MAX_WAIT={{timeout}}  # Maximum wait time in seconds
    ELAPSED=0

    while [ $ELAPSED -lt $MAX_WAIT ]; do
        INSTANCES=$(curl {{NETCLICS_CURL_OPTS}} -s {{NETCLICS_BASE_URL}}/api/v1/instances)

        # Check if any instances are not ready
        NOT_READY=$(echo "$INSTANCES" | jq -r '.instances[] | select(.state != "ready") | "\(.instance_id): \(.state)"')

        if [ -z "$NOT_READY" ]; then
            echo "All instances are ready!"
            exit 0
        fi

        echo "Waiting for instances to be ready ($ELAPSED/$MAX_WAIT seconds):"
        echo "$NOT_READY"
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    echo "Timeout waiting for instances to be ready after $MAX_WAIT seconds"
    exit 1

# Wait for all schemas to be compiled
# Usage: just wait-for-schemas [timeout_seconds]
# Default timeout: 360 seconds
wait-for-schemas timeout="360":
    #!/usr/bin/env bash
    echo "Waiting for all schemas to be compiled..."

    MAX_WAIT={{timeout}}  # Maximum wait time in seconds
    ELAPSED=0

    while [ $ELAPSED -lt $MAX_WAIT ]; do
        INSTANCES=$(curl {{NETCLICS_CURL_OPTS}} -s {{NETCLICS_BASE_URL}}/api/v1/instances)

        # First check if there are any instances
        INSTANCE_COUNT=$(echo "$INSTANCES" | jq '.instances | length')
        if [ "$INSTANCE_COUNT" -eq 0 ]; then
            echo "No instances found. Ensure NETCLICS server is running with instances."
            exit 1
        fi

        # Check if all module sets are compiled
        NOT_COMPILED=$(echo "$INSTANCES" | \
            jq -r '.instances[] | .instance_id as $id | .module_sets | to_entries[] | select(.value.compiled == false) | "\($id)/\(.key): \(.value.error // "compiling...")"')

        if [ -z "$NOT_COMPILED" ]; then
            echo "All schemas compiled successfully!"
            exit 0
        fi

        echo "Compiling schemas ($ELAPSED/$MAX_WAIT seconds):"
        echo "$NOT_COMPILED"
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    echo "Timeout waiting for schemas to compile after $MAX_WAIT seconds"
    exit 1

# Wait for both instances to be ready and schemas to be compiled
# Usage: just wait-for-all [instances_timeout] [schemas_timeout]
# Default timeouts: 180 seconds for instances, 180 seconds for schemas
wait-for-all instances_timeout="180" schemas_timeout="180":
    just wait-for-instances {{instances_timeout}}
    just wait-for-schemas {{schemas_timeout}}

# Test multi-step configuration
test-multi-step:
    #!/usr/bin/env bash
    echo "=== Multi-Step Configuration Test ==="
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": [
          "set policy-options prefix-list RFC1918 10.0.0.0/8",
          "set policy-options policy-statement REJECT-PRIVATE term 1 from prefix-list RFC1918"
        ],
        "format": "cli",
        "target_format": "netconf",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Step-by-Step Summary ==="
    echo "$RESULT" | jq -r '.steps[] | "Step: \(.input)\nHas diff: \(if .diff == "" then "No" else "Yes" end)\n"'

# Test multi-step CLI -> NETCONF for IOS XE
test-multi-step-iosxe:
    #!/usr/bin/env bash
    echo "=== Multi-Step IOS XE Configuration Test (CLI -> NETCONF) ==="
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": [
          "interface GigabitEthernet2\n description Test Interface",
          "interface GigabitEthernet2\n ip address 192.168.1.1 255.255.255.0"
        ],
        "format": "cli",
        "target_format": "netconf",
        "platform": "iosxe 17.18.02-local"
      }')
    echo "$RESULT" | jq .

# Test multi-step CLI -> NETCONF for IOS XR
test-multi-step-iosxr:
    #!/usr/bin/env bash
    echo "=== Multi-Step IOS XR Configuration Test (CLI -> NETCONF) ==="
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": [
          "interface GigabitEthernet0/0/0/1\n description XR Test Interface",
          "interface GigabitEthernet0/0/0/1\n ipv4 address 10.1.1.1 255.255.255.0"
        ],
        "format": "cli",
        "target_format": "netconf",
        "platform": "iosxrd 24.1.1-local"
      }')
    echo "$RESULT" | jq .

# Test multi-step CLI -> CLI (useful for verifying CLI normalization)
test-multi-step-cli-to-cli:
    #!/usr/bin/env bash
    echo "=== Multi-Step CLI -> CLI Test (cRPD) ==="
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": [
          "set interfaces ge-0/0/1 description \"Test Port\"",
          "set interfaces ge-0/0/1 unit 0 family inet address 10.0.0.1/24"
        ],
        "format": "cli",
        "target_format": "cli",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Checking CLI diffs ==="
    echo "$RESULT" | jq -r '.steps[] | "Input: \(.input)\nDiff:\n\(.diff)\n---"'

# Test multi-step NETCONF -> CLI
test-multi-step-netconf-to-cli:
    #!/usr/bin/env bash
    echo "=== Multi-Step NETCONF -> CLI Test (cRPD) ==="
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": [
          "<configuration><interfaces><interface><name>ge-0/0/2</name><description>NETCONF Test</description></interface></interfaces></configuration>",
          "<configuration><interfaces><interface><name>ge-0/0/2</name><unit><name>0</name><family><inet><address><name>172.16.0.1/24</name></address></inet></family></unit></interface></interfaces></configuration>"
        ],
        "format": "netconf",
        "target_format": "cli",
        "platform": "crpd 24.4R1.9-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Checking CLI diffs ==="
    echo "$RESULT" | jq -r '.steps[] | "Input: \(.input)\nDiff:\n\(.diff)\n---"'

# Test multi-step CLI -> CLI for IOS XE (verifies archive cleaning)
test-multi-step-iosxe-cli-to-cli:
    #!/usr/bin/env bash
    echo "=== Multi-Step CLI -> CLI Test (IOS XE) ==="
    RESULT=$(curl {{NETCLICS_CURL_OPTS}} -s -X POST {{NETCLICS_BASE_URL}}/api/v1/convert \
      -H "Content-Type: application/json" \
      -d '{
        "input": [
          "interface GigabitEthernet3\n description \"First step - description only\"",
          "interface GigabitEthernet3\n ip address 192.168.10.1 255.255.255.0",
          "interface GigabitEthernet3\n no shutdown"
        ],
        "format": "cli",
        "target_format": "cli",
        "platform": "iosxe 17.18.02-local"
      }')
    echo "$RESULT" | jq .

    echo ""
    echo "=== Checking CLI diffs for each step ==="
    echo "$RESULT" | jq -r '.steps[] | "Step Input:\n\(.input)\n\nResulting Diff:\n\(.diff)\n================================"'

# Test all multi-step scenarios across all platforms and format combinations
test-multi-step-all: test-multi-step test-multi-step-iosxe test-multi-step-iosxr test-multi-step-cli-to-cli test-multi-step-netconf-to-cli test-multi-step-iosxe-cli-to-cli
    @echo "All multi-step tests completed"

# Clean up build artifacts
clean:
    rm -rf out/ .acton.lock *.log
