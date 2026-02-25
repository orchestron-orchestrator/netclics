# netclics - NETCONF <> CLI Conversion System
[![REUSE Compliance Check](https://github.com/orchestron-orchestrator/netclics/actions/workflows/reuse-compliance.yml/badge.svg)](https://github.com/orchestron-orchestrator/netclics/actions/workflows/reuse-compliance.yml)

NETCLICS converts CLI configuration to NETCONF XML / RESTCONF JSON and vice versa. This is performed by round-tripping the configuration through virtual devices, like crpd (containerized JUNOS) or XRd (containerized IOS XR).

## Endpoints

By default, NETCLICS listens on HTTP `:8080`.

To enable HTTPS, start with:

```bash
out/bin/netclics --https-port 8443 --tls-cert /path/to/cert.pem --tls-key /path/to/key.pem
```

Notes:
- `--http-port 0` disables HTTP.
- HTTPS is enabled only when `--https-port`, `--tls-cert`, and `--tls-key` are all provided.

## Configuration File

NETCLICS loads configuration from `config/netclics.json` by default.

Use a different file with:

```bash
out/bin/netclics --config /path/to/netclics.json
```

After editing the config file, reload it without restarting:

```bash
curl -s -X POST http://localhost:8080/api/v1/config/reload | jq .
```

Or with Just:

```bash
just reload-config
```
