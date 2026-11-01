# ATS probe results (iOS 27.1 simulator, Octavo Trust Duo, 2026-11-01)

App-hosted test, one URLSession request per URL (4 s timeout). -1022 = ATS blocked; -1001/-1003/-1004 = ATS let it through (timeout, no such host, refused). 192.168.1.122 is the Mac's Wi-Fi address with BookOrbit on :3300.

## 1. NSAllowsLocalNetworking only

```
http://192.168.1.122:3300/api/v1/health → HTTP 200
http://127.0.0.1:3300/api/v1/health → HTTP 200
http://localhost:3300/api/v1/health → HTTP 200
http://localhost.:3300/api/v1/health → -1022
http://[::1]:3300/api/v1/health → -1004
http://[::ffff:192.168.1.122]:3300/api/v1/health → HTTP 200
http://[::ffff:c0a8:17a]:3300/api/v1/health → HTTP 200
http://[::ffff:127.0.0.1]:3300/api/v1/health → HTTP 200
http://192.168.1.122.:3300/api/v1/health → -1022
http://3232235898:3300/api/v1/health → HTTP 200
http://2130706433:3300/api/v1/health → HTTP 200
http://0x7f000001:3300/api/v1/health → HTTP 200
http://0177.0.0.1:3300/api/v1/health → -1022
http://127.1:3300/api/v1/health → -1022
http://0300.0250.1.0172:3300/api/v1/health → -1022
http://100.100.100.100:9/ → -1022
http://10.255.255.1:9/ → -1001
http://169.254.1.1:9/ → -1001
http://[fd00::1]:9/ → -1001
http://[fe80::1%25en0]:9/ → -1001
http://1.1.1.1/ → -1022
http://[2606:4700:4700::1111]/ → -1022
http://[::ffff:1.1.1.1]/ → -1022
http://16843009/ → HTTP 403   (1.1.1.1: Cloudflare answered over plain http)
http://nas:9/ → -1003
http://nas.local:9/ → -1001
http://nas.lan:9/ → -1022
http://nas.home.arpa:9/ → -1022
http://nas.internal:9/ → -1022
http://bücher.local:9/ (host b%C3%BCcher.local) → -1001
http://192-168-1-122.sslip.io:3300/api/v1/health → -1022
http://example.com/ → -1022
```

## 2. + NSExceptionDomains (100.64.0.0/10; lan, internal, home.arpa, ts.net, sslip.io with subdomains; insecure HTTP)

```
http://192.168.1.122:3300/api/v1/health host=192.168.1.122 → HTTP 200
http://127.0.0.1:3300/api/v1/health host=127.0.0.1 → HTTP 200
http://localhost:3300/api/v1/health host=localhost → HTTP 200
http://localhost.:3300/api/v1/health host=localhost. → URLError -1022
http://[::1]:3300/api/v1/health host=::1 → URLError -1004
http://[::ffff:192.168.1.122]:3300/api/v1/health host=::ffff:192.168.1.122 → HTTP 200
http://[::ffff:c0a8:17a]:3300/api/v1/health host=::ffff:c0a8:17a → HTTP 200
http://[::ffff:127.0.0.1]:3300/api/v1/health host=::ffff:127.0.0.1 → HTTP 200
http://192.168.1.122.:3300/api/v1/health host=192.168.1.122. → URLError -1022
http://3232235898:3300/api/v1/health host=3232235898 → HTTP 200
http://2130706433:3300/api/v1/health host=2130706433 → HTTP 200
http://0x7f000001:3300/api/v1/health host=0x7f000001 → HTTP 200
http://0177.0.0.1:3300/api/v1/health host=0177.0.0.1 → URLError -1022
http://127.1:3300/api/v1/health host=127.1 → URLError -1022
http://0300.0250.1.0172:3300/api/v1/health host=0300.0250.1.0172 → URLError -1022
http://100.100.100.100:9/ host=100.100.100.100 → URLError -1004
http://10.255.255.1:9/ host=10.255.255.1 → URLError -1001
http://169.254.1.1:9/ host=169.254.1.1 → URLError -1001
http://[fd00::1]:9/ host=fd00::1 → URLError -1001
http://[fe80::1%25en0]:9/ host=fe80::1%25en0 → URLError -1001
http://1.1.1.1/ host=1.1.1.1 → URLError -1022
http://[2606:4700:4700::1111]/ host=2606:4700:4700::1111 → URLError -1022
http://[::ffff:1.1.1.1]/ host=::ffff:1.1.1.1 → URLError -1022
http://16843009/ host=16843009 → HTTP 403
http://nas:9/ host=nas → URLError -1003
http://nas.local:9/ host=nas.local → URLError -1001
http://nas.lan:9/ host=nas.lan → URLError -1003
http://nas.home.arpa:9/ host=nas.home.arpa → URLError -1003
http://nas.internal:9/ host=nas.internal → URLError -1003
http://bücher.local:9/ host=b%C3%BCcher.local → URLError -1001
http://192-168-1-122.sslip.io:3300/api/v1/health host=192-168-1-122.sslip.io → HTTP 200
http://example.com/ host=example.com → URLError -1022
http://100.64.0.1:9/ host=100.64.0.1 → URLError -1001
http://nas.ts.net:9/ host=nas.ts.net → URLError -1003
http://[fd7a:115c:a1e0::1]:9/ host=fd7a:115c:a1e0::1 → URLError -1001
http://nas.lan.:9/ host=nas.lan. → URLError -1022```

## 3. NSAllowsArbitraryLoads only

```
http://192.168.1.122:3300/api/v1/health host=192.168.1.122 → HTTP 200
http://127.0.0.1:3300/api/v1/health host=127.0.0.1 → HTTP 200
http://localhost:3300/api/v1/health host=localhost → HTTP 200
http://localhost.:3300/api/v1/health host=localhost. → HTTP 200
http://[::1]:3300/api/v1/health host=::1 → URLError -1004
http://[::ffff:192.168.1.122]:3300/api/v1/health host=::ffff:192.168.1.122 → HTTP 200
http://[::ffff:c0a8:17a]:3300/api/v1/health host=::ffff:c0a8:17a → HTTP 200
http://[::ffff:127.0.0.1]:3300/api/v1/health host=::ffff:127.0.0.1 → HTTP 200
http://192.168.1.122.:3300/api/v1/health host=192.168.1.122. → URLError -1003
http://3232235898:3300/api/v1/health host=3232235898 → HTTP 200
http://2130706433:3300/api/v1/health host=2130706433 → HTTP 200
http://0x7f000001:3300/api/v1/health host=0x7f000001 → HTTP 200
http://0177.0.0.1:3300/api/v1/health host=0177.0.0.1 → URLError -1001
http://127.1:3300/api/v1/health host=127.1 → HTTP 200
http://0300.0250.1.0172:3300/api/v1/health host=0300.0250.1.0172 → HTTP 200
http://100.100.100.100:9/ host=100.100.100.100 → URLError -1004
http://10.255.255.1:9/ host=10.255.255.1 → URLError -1001
http://169.254.1.1:9/ host=169.254.1.1 → URLError -1001
http://[fd00::1]:9/ host=fd00::1 → URLError -1001
http://[fe80::1%25en0]:9/ host=fe80::1%25en0 → URLError -1001
http://1.1.1.1/ host=1.1.1.1 → HTTP 200
http://[2606:4700:4700::1111]/ host=2606:4700:4700::1111 → HTTP 200
http://[::ffff:1.1.1.1]/ host=::ffff:1.1.1.1 → HTTP 403
http://16843009/ host=16843009 → HTTP 403
http://nas:9/ host=nas → URLError -1003
http://nas.local:9/ host=nas.local → URLError -1001
http://nas.lan:9/ host=nas.lan → URLError -1003
http://nas.home.arpa:9/ host=nas.home.arpa → URLError -1003
http://nas.internal:9/ host=nas.internal → URLError -1003
http://bücher.local:9/ host=b%C3%BCcher.local → URLError -1001
http://192-168-1-122.sslip.io:3300/api/v1/health host=192-168-1-122.sslip.io → HTTP 200
http://example.com/ host=example.com → HTTP 200
http://100.64.0.1:9/ host=100.64.0.1 → URLError -1001
http://nas.ts.net:9/ host=nas.ts.net → URLError -1003
http://[fd7a:115c:a1e0::1]:9/ host=fd7a:115c:a1e0::1 → URLError -1001
http://nas.lan.:9/ host=nas.lan. → URLError -1003
http://192.168.378:3300/api/v1/health host=192.168.378 → HTTP 200
http://0xc0.0xa8.0x1.0x7a:3300/api/v1/health host=0xc0.0xa8.0x1.0x7a → HTTP 200
http://192.168.001.122:3300/api/v1/health host=192.168.001.122 → HTTP 200
http://[::192.168.1.122]:3300/api/v1/health host=::192.168.1.122 → URLError -1001
http://[64:ff9b::c0a8:17a]:3300/api/v1/health host=64:ff9b::c0a8:17a → URLError -1001
http://LOCALHOST:3300/api/v1/health host=LOCALHOST → HTTP 200
http://xn--bcher-kva.local:9/ host=xn--bcher-kva.local → URLError -1001```

## Self-signed certificate, delegate returning .useCredential ("accept") vs none ("default")

NSAllowsLocalNetworking only: accepted on 192.168.1.122, localhost and 127.0.0.1; -1200 (ATS) on 192-168-1-122.sslip.io and .nip.io. With an NSExceptionDomains entry for sslip.io (insecure HTTP allowed): accepted there too; nip.io still -1200. Without the delegate: -1202 everywhere.
