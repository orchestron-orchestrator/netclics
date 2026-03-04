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

## Static file server, ACME HTTP-01 challenge

To serve static files for non-API GET paths:

```bash
out/bin/netclics --static-dir /path/to/public_html
```

This is also useful for integrating NETCLICS with [certbot](https://certbot.eff.org). If you configure certbot to use the same web root using the option `--webroot /path/to/public_html`, then it will automatically create the `/.well-known/token/...` response for the HTTP-01 challenge.

## Configuration File

NETCLICS loads configuration from `config/netclics.json` by default.

Use a different file with:

```bash
out/bin/netclics --config /path/to/netclics.json
```

After editing the config file, save it and it will be automatically reloaded.
