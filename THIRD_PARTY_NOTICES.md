# Third-party notices

## lwIP 2.2.1

Source: https://github.com/lwip-tcpip/lwip/tree/STABLE-2_2_1_RELEASE
Pinned tag: STABLE-2_2_1_RELEASE.
License: BSD-3-Clause; see `entry/src/main/cpp/vendor/lwip/COPYING` and copyright/license headers in individual source files. They must remain in source distributions. Binary distributions must reproduce these notices in accompanying documentation.

The vendored `src` directory and COPYING are unmodified upstream files. The `lwip_port` configuration and `tcp_relay.cpp` integration are application code. Only core/IPv4 files are built; no lwIP apps, OS socket compatibility layer, PPP, or TLS library is linked. No Android dependencies are included.

This project does not include PCAPdroid or its MITM add-on. Their documentation was consulted for the distinction between VPN transport and TLS decryption.
