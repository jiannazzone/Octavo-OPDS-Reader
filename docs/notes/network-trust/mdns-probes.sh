#!/bin/zsh
# Registers three .local names over Bonjour, as a hostile device on the
# Wi-Fi could, for the simulator's live DNS test (step 16,
# NetworkTrustLiveTests.namesAreJudgedByWhereTheyResolve):
#   octavo-probe-public.local → 203.0.113.7 (TEST-NET-3, never answers)
#   octavo-probe-v6.local     → 2001:db8::7 (documentation prefix)
#   octavo-probe-home.local   → 192.168.1.250
# Usage: mdns-probes.sh start | stop
set -e
case "$1" in
start)
    dns-sd -P "Octavo probe public" _octavoprobe._tcp local 3300 octavo-probe-public.local 203.0.113.7 >/dev/null 2>&1 &
    dns-sd -P "Octavo probe v6" _octavoprobe._tcp local 3300 octavo-probe-v6.local 2001:db8::7 >/dev/null 2>&1 &
    dns-sd -P "Octavo probe home" _octavoprobe._tcp local 3300 octavo-probe-home.local 192.168.1.250 >/dev/null 2>&1 &
    sleep 2
    dscacheutil -q host -a name octavo-probe-public.local | grep address
    ;;
stop)
    pkill -f "dns-sd -P Octavo probe" || true
    ;;
*)
    echo "usage: $0 start|stop" >&2
    exit 64
    ;;
esac
