# Cloudflare DNS Update Script

A bash script to update a single DNS record on Cloudflare (DDNS - Dynamic DNS).

## Prerequisites

- `jq` - JSON parsing
- `curl` - HTTP requests

## Configuration

Create a `.env` file in the script directory with the following variables:

```bash
CF_API_TOKEN=your_cloudflare_api_token
CF_ZONE_ID=your_zone_id
CF_RECORD_ID=your_dns_record_id
```

### Getting Cloudflare Credentials

1. **CF_API_TOKEN**: Create an API token in Cloudflare Dashboard with "Zone / DNS / Edit" permission
2. **CF_ZONE_ID**: Found in the URL when viewing your zone (32-char hex)
3. **CF_RECORD_ID**: Can be obtained via Cloudflare API

## Usage

```bash
# Update to current public IP
./cf_update_dns.sh

# Force a specific IP address
./cf_update_dns.sh --ip 192.0.2.5

# Update with custom options
./cf_update_dns.sh --proxied false --ttl 3600
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--name` | DNS record name | Current Cloudflare value |
| `--type` | Record type (A/AAAA/CNAME) | Current type |
| `--ttl` | TTL (300/3600/1 for Auto) | Current TTL |
| `--proxied` | Enable/disable proxy | Current value |
| `--ip` | Force specific IP | Auto-detect public IP |

## Automating with Cron

Add to crontab to run periodically:

```cron
*/15 * * * * /path/to/cf_update_dns.sh >> /path/to/logs/cf_ddns.log 2>&1
```

## Automating with Systemd

Alternatively, you can use systemd timer (recommended for modern systems).

### Installation

```bash
# Copy service and timer files to systemd directory
sudo cp cf-ddns.service /etc/systemd/system/
sudo cp cf-ddns.timer /etc/systemd/system/

# Reload systemd and enable the timer
sudo systemctl daemon-reload
sudo systemctl enable --now cf-ddns.timer
```

### Commands

```bash
# Check timer status
sudo systemctl status cf-ddns.timer

# View logs
sudo journalctl -u cf-ddns.service

# Manually trigger an update
sudo systemctl start cf-ddns.service

# View the log file (same format as crontab)
tail -f /home/labban/dns-ip-update/logs/cf_ddns.log
```

The timer runs every 15 minutes (same as `*/15 * * * *`).
