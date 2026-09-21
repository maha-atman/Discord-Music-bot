#!/bin/sh
# Container entrypoint.
#
# Some ISPs (Indonesia's "Internet Positif") rewrite plain DNS answers for certain
# domains to a complaint-landing page, so anything using the system resolver —
# reqwest, yt-dlp, ffmpeg — fails with a connect error while the site itself stays
# reachable. DNS-over-HTTPS is not intercepted, so at startup we resolve the pinned
# hosts over DoH and add the real addresses to /etc/hosts, which glibc consults
# before DNS.
#
# Safe to run on a clean network: the resolved addresses are the same ones DNS would
# return, and if the lookup fails we simply start without pinning.
set -eu

HOSTS_TO_PIN="${DNS_PIN_HOSTS:-www.jasmr.net}"
DOH_ENDPOINT="${DNS_DOH_ENDPOINT:-https://cloudflare-dns.com/dns-query}"

pin_host() {
    host="$1"
    ips=$(curl -fsS --max-time 10 -H 'accept: application/dns-json' \
        "${DOH_ENDPOINT}?name=${host}&type=A" 2>/dev/null \
        | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
print(" ".join(a["data"] for a in data.get("Answer", []) if a.get("type") == 1))' 2>/dev/null) || ips=""

    if [ -z "${ips}" ]; then
        echo "[entrypoint] ${host}: DoH lookup unavailable, leaving DNS as-is"
        return 0
    fi

    for ip in ${ips}; do
        if grep -q "^${ip}[[:space:]]\+${host}$" /etc/hosts 2>/dev/null; then
            continue
        fi
        echo "${ip} ${host}" >> /etc/hosts
        echo "[entrypoint] pinned ${host} -> ${ip} (DoH)"
    done
}

for host in ${HOSTS_TO_PIN}; do
    pin_host "${host}"
done

exec /app/discord-music-bot "$@"
