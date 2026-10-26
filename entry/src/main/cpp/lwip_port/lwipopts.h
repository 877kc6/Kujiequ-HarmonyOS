#pragma once
#define NO_SYS 1
#define SYS_LIGHTWEIGHT_PROT 0
#define LWIP_SOCKET 0
#define LWIP_NETCONN 0
#define LWIP_IPV4 1
#define LWIP_IPV6 0
#define LWIP_ARP 0
#define LWIP_ETHERNET 0
#define LWIP_ICMP 0
#define LWIP_UDP 0
#define LWIP_RAW 0
#define LWIP_DHCP 0
#define LWIP_AUTOIP 0
#define LWIP_DNS 0
#define LWIP_IGMP 0
#define LWIP_TCP 1
#define LWIP_TIMERS 1
#define MEM_ALIGNMENT 8
#define MEM_SIZE (128 * 1024)
#define MEMP_NUM_TCP_PCB 8
#define MEMP_NUM_TCP_PCB_LISTEN 2
#define MEMP_NUM_TCP_SEG 128
#define PBUF_POOL_SIZE 64
#define TCP_MSS 1360
#define TCP_WND (16 * TCP_MSS)
#define TCP_SND_BUF (16 * TCP_MSS)
#define TCP_SND_QUEUELEN 64
#define LWIP_STATS 0
#define IP_REASSEMBLY 0
#define IP_FRAG 0
#define LWIP_NETIF_HOSTNAME 0
#define LWIP_NETIF_STATUS_CALLBACK 0
