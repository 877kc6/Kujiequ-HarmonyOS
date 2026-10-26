# Real game traffic integration (not yet implemented)

The existing VPN route uses a host-only synthetic /32 target and trustedApplications restricted to this application. Its native module tests TCP/HTTPS probes, not actual game sessions. Do not toggle the VPN to global routing before a complete fail-open, multi-flow TCP/UDP/DNS relay is verified, or games may lose connectivity.

Milestone A: opt-in game selection, per-app VPN authorization, IPv4 TCP/UDP/DNS with concurrent flows, per-flow timeouts, IPv6 handling, and clean teardown; verify normal game login and gameplay on device.

Milestone B: optional local proxy for connections explicitly configured to use it; show certificate-install instructions and consent. Test whether the game trusts user-installed CA certificates. Certificate pinning, app trust policies and TLS 1.3 mean decryption may be unavailable; do not bypass those protections. No CA private key should be embedded in distributable source.

Milestone C: parse only user-authorized gacha-history requests, redact access credentials from diagnostics, encrypt stored session data, obtain records via authorized official interfaces where permitted, and implement revocation/deletion. No credential extraction from unrelated traffic.

No current claim of game support, decryption, or token extraction is justified by the probe tests.
