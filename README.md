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

To serve static files under an explicit URL prefix:

```bash
out/bin/netclics --static-dir /path/to/public_html
```

By default, NETCLICS serves that directory under `/static/...`. Use `--static-prefix` to change the mount point:

```bash
out/bin/netclics --static-dir /path/to/public_html --static-prefix /assets
```

This is also useful for integrating NETCLICS with [certbot](https://certbot.eff.org). Configure NETCLICS and certbot to use the same web root:

```bash
out/bin/netclics --static-dir /path/to/public_html --static-prefix /.well-known
certbot certonly --webroot -w /path/to/public_html ...
```

Certbot will then create files under `/path/to/public_html/.well-known/...`, and NETCLICS will serve them at `/.well-known/...`.

## Configuration File

NETCLICS loads configuration from `config/netclics.json` by default.

Use a different file with:

```bash
out/bin/netclics --config /path/to/netclics.json
```

After editing the config file, save it and it will be automatically reloaded.
