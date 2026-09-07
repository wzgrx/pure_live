# Loopback TLS test material

This self-signed certificate and publicly committed test-only private key are for
local automated fixtures only. Never deploy or trust this key in an application,
system trust store, or external service. Tests explicitly load this certificate
into an isolated SecurityContext; production uses the platform default trust.

SAN: DNS localhost only (the IP address is deliberately not covered).
Validity: 2020-01-01 through 2040-01-01. Serial: 42.
Generated with a 2048-bit RSA key and SHA-256 signature. No external CA is used.

`wrong-host-cert.pem` uses the same public test key and validity with serial 43,
but SAN DNS wrong-host.invalid. Tests trust that chain in isolation and still
require rejection when connecting to localhost, including through HTTP CONNECT.
