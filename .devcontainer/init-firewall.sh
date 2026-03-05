#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

ALLOWED_DOMAINS_CONF="/etc/allowed-domains.conf"

# Skip if already configured (postStartCommand runs on every start).
# Check iptables policy rather than a lock file, because iptables rules are
# cleared on container restart while a lock file would persist on the filesystem.
if iptables -L OUTPUT -n 2>/dev/null | grep -q "policy DROP"; then
  echo "Firewall already configured, skipping."
  exit 0
fi

# Install firewall dependencies if not present
if ! command -v iptables &>/dev/null || ! command -v ipset &>/dev/null || ! command -v dig &>/dev/null || ! command -v aggregate &>/dev/null || ! command -v jq &>/dev/null; then
  echo "Installing firewall dependencies..."
  apt-get update && apt-get install -y --no-install-recommends \
    iptables ipset iproute2 dnsutils aggregate jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
fi

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127.0.0.11" || true)

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Apply IPv6 default DROP (minimal, no exceptions needed for dev work)
if command -v ip6tables &>/dev/null; then
  ip6tables -P INPUT DROP
  ip6tables -P FORWARD DROP
  ip6tables -P OUTPUT DROP
  ip6tables -A INPUT -i lo -j ACCEPT
  ip6tables -A OUTPUT -o lo -j ACCEPT
fi

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
  echo "Restoring Docker DNS rules..."
  iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
  iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
  echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
  echo "No Docker DNS rules to restore"
fi

# Allow DNS to configured resolvers (read from /etc/resolv.conf)
# Supports both Docker Desktop for macOS (192.168.65.7) and Linux Docker (127.0.0.11)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
while IFS= read -r dns_ip; do
  echo "Allowing DNS to resolver: $dns_ip"
  iptables -A OUTPUT -d "$dns_ip" -p udp --dport 53 -j ACCEPT
  iptables -A OUTPUT -d "$dns_ip" -p tcp --dport 53 -j ACCEPT
  iptables -A INPUT -s "$dns_ip" -p udp --sport 53 -j ACCEPT
  iptables -A INPUT -s "$dns_ip" -p tcp --sport 53 -j ACCEPT
done < <(awk '/^nameserver/ {print $2}' /etc/resolv.conf)

# Create staging ipset (atomic swap on success)
ipset destroy allowed-domains-staging 2>/dev/null || true
ipset destroy allowed-domains 2>/dev/null || true
ipset create allowed-domains-staging hash:net

# Fetch GitHub meta information and add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s --retry 2 --connect-timeout 10 https://api.github.com/meta || true)

if [ -z "$gh_ranges" ] || ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
  echo "WARNING: Failed to fetch GitHub IP ranges from API, falling back to DNS resolution"
  for gh_domain in github.com api.github.com objects.githubusercontent.com; do
    echo "Resolving fallback $gh_domain..."
    ips=$(dig +noall +answer A "$gh_domain" | awk '$4 == "A" {print $5}')
    while read -r ip; do
      [ -n "$ip" ] && ipset add -exist allowed-domains-staging "$ip"
    done < <(echo "$ips")
  done
else
  echo "Processing GitHub IPs..."
  while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
      echo "WARNING: Skipping invalid CIDR from GitHub meta: $cidr"
      continue
    fi
    echo "Adding GitHub range $cidr"
    ipset add -exist allowed-domains-staging "$cidr"
  done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | grep -E '^[0-9]+\.' | aggregate -q)
fi

# Resolve and add allowed domains from config file
if [ ! -f "$ALLOWED_DOMAINS_CONF" ]; then
  echo "WARNING: $ALLOWED_DOMAINS_CONF not found, skipping domain allowlist"
else
  while IFS= read -r domain; do
    domain=$(echo "$domain" | sed 's/#.*//' | xargs)
    [ -z "$domain" ] && continue

    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')

    if [ -z "$ips" ]; then
      echo "WARNING: Failed to resolve $domain, retrying in 2s..."
      sleep 2
      ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    fi

    if [ -z "$ips" ]; then
      echo "WARNING: Still failed to resolve $domain, skipping"
      continue
    fi

    while read -r ip; do
      if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "WARNING: Invalid IP from DNS for $domain: $ip, skipping"
        continue
      fi
      echo "Adding $ip for $domain"
      ipset add -exist allowed-domains-staging "$ip"
    done < <(echo "$ips")
  done < "$ALLOWED_DOMAINS_CONF"
fi

# Atomically activate the new ipset
ipset rename allowed-domains-staging allowed-domains

# Resolve host-side network from default route interface
DEFAULT_IFACE=$(ip -4 route show default | awk '{print $5; exit}')
if [ -z "$DEFAULT_IFACE" ]; then
  echo "ERROR: Failed to detect default route interface"
  exit 1
fi

HOST_NETWORK=$(ip -4 route show dev "$DEFAULT_IFACE" | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ {print $1; exit}')
if [ -z "$HOST_NETWORK" ]; then
  echo "ERROR: Failed to detect host network for interface $DEFAULT_IFACE"
  exit 1
fi

echo "Host network detected as: $HOST_NETWORK"

# Set up iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Log blocked connections (rate limited)
iptables -A OUTPUT -m limit --limit 5/min -j LOG --log-prefix "[FW-BLOCKED] " --log-level 4
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - was able to reach https://example.com"
  exit 1
else
  echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
  exit 1
else
  echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

# --- Lockdown: prevent in-container modification of firewall ---
echo "Locking down firewall tools..."

# Restrict firewall binaries to root-only execution
for bin in iptables iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore ipset; do
  bin_path=$(which "$bin" 2>/dev/null) && chmod 700 "$bin_path" 2>/dev/null || true
done

# Remove blanket passwordless sudo grants.
# Keep the init-firewall.sh-specific entry (needed for container restarts).
# The dev-firewall sudoers file grants only /usr/local/bin/init-firewall.sh,
# so it cannot be used to run arbitrary commands as root.
rm -f /etc/sudoers.d/dev /etc/sudoers.d/vscode 2>/dev/null || true

# Add firewall-status.sh to the existing dev-firewall sudoers entry
echo "dev ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /usr/local/bin/firewall-status.sh" \
  > /etc/sudoers.d/dev-firewall
chmod 0440 /etc/sudoers.d/dev-firewall

echo "Firewall locked down. Use 'sudo firewall-status.sh' to inspect."
