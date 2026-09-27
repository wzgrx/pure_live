# Loopback TLS test material

This self-signed certificate and publicly committed test-only private key are for
local automated fixtures only. Never deploy or trust this key in an application,
system trust store, or external service. Tests explicitly load this certificate
into an isolated SecurityContext; production uses the platform default trust.

The repository audit reports this public fixture by exact path and SHA-256
`b55b3743dda7dd512713f6efa4850d3a729486e9e2bff8cb4302738c192a5af8`.
It does not exempt other PEM files or the test directory. Changed bytes, another
path, or an appended credential fail the ordinary secret gate. Keep LF endings.

SAN: DNS localhost only (the IP address is deliberately not covered).
Validity: 2020-01-01 through 2040-01-01. Serial: 42.
Generated with a 2048-bit RSA key and SHA-256 signature. No external CA is used.

`wrong-host-cert.pem` uses the same public test key and validity with serial 43,
but SAN DNS wrong-host.invalid. Tests trust that chain in isolation and still
require rejection when connecting to localhost, including through HTTP CONNECT.
