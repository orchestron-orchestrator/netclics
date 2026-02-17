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
- `--port 0` disables HTTP.
- HTTPS is enabled only when `--https-port`, `--tls-cert`, and `--tls-key` are all provided.
