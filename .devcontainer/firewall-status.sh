#!/bin/bash
echo "=== Allowed IPs ==="
ipset list allowed-domains 2>/dev/null | head -50 || echo "Cannot read ipset"

echo ""
echo "=== Blocked connections (last 20) ==="
dmesg 2>/dev/null | grep "FW-BLOCKED" | tail -20 || echo "No blocked connections logged"

echo ""
echo "=== Quick connectivity test ==="
curl -s --connect-timeout 3 https://api.github.com/zen && echo " (GitHub: OK)" || echo "(GitHub: FAIL)"
curl -s --connect-timeout 3 https://example.com >/dev/null 2>&1 \
  && echo "(example.com: REACHABLE - UNEXPECTED)" \
  || echo "(example.com: Blocked - OK)"
