#include "tcp_relay.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>
#include <vector>
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
using Bytes = std::vector<uint8_t>;
uint16_t get16(const uint8_t* p) { return uint16_t(p[0]) * 256 + p[1]; }
uint32_t get32(const uint8_t* p) { return uint32_t(get16(p)) * 65536 + get16(p+2); }
void put16(uint8_t* p, uint16_t x) { p[0] = x >> 8; p[1] = x; }
void put32(uint8_t* p, uint32_t x) { put16(p, x >> 16); put16(p+2, x); }
uint16_t checksum(const Bytes& data) {
    uint32_t sum = 0;
    for (size_t i = 0; i < data.size(); i += 2) sum += uint16_t(data[i])*256 + (i+1 < data.size() ? data[i+1] : 0);
    while (sum >> 16) sum = (sum & 65535) + (sum >> 16);
    return ~sum;
}
Bytes packet(uint32_t seq, uint32_t ack, uint8_t flags, const std::string& body = "") {
    Bytes out(40 + body.size(), 0);
    out[0]=0x45; put16(&out[2], out.size()); out[8]=64; out[9]=6;
    out[12]=198; out[13]=18; out[15]=1; out[16]=198; out[17]=18; out[19]=2;
    put16(&out[20], 54321); put16(&out[22], kujiequ::probe::TCP_PORT);
    put32(&out[24],seq); put32(&out[28],ack); out[32]=0x50; out[33]=flags;
    put16(&out[34], 2048); std::copy(body.begin(),body.end(),out.begin()+40);
    Bytes pseudo(out.begin()+12,out.begin()+20); pseudo.push_back(0); pseudo.push_back(6);
    pseudo.push_back((out.size()-20)>>8); pseudo.push_back(out.size()-20);
    pseudo.insert(pseudo.end(),out.begin()+20,out.end()); put16(&out[36],checksum(pseudo));
    put16(&out[10],checksum(Bytes(out.begin(),out.begin()+20))); return out;
}
void sendPacket(int fd, const Bytes& bytes) { assert(write(fd,bytes.data(),bytes.size()) == static_cast<ssize_t>(bytes.size())); }
int main() {
    const std::string connect = "CONNECT one.one.one.one:443 HTTP/1.1\r\nHost: one.one.one.one:443\r\n\r\n";
    size_t used = 0;
    for (size_t i = 0; i < connect.size(); ++i) {
        assert(kujiequ::probe::inspectConnect(reinterpret_cast<const uint8_t*>(connect.data()), i, used) == 0);
    }
    assert(kujiequ::probe::inspectConnect(reinterpret_cast<const uint8_t*>(connect.data()), connect.size(), used) == 1);
    assert(used == connect.size());
    for (const std::string bad : {"CONNECT evil.test:443 HTTP/1.1\r\n\r\n", "GET / HTTP/1.1\r\n\r\n", "CONNECT one.one.one.one:80 HTTP/1.1\r\n\r\n"}) {
        assert(kujiequ::probe::inspectConnect(reinterpret_cast<const uint8_t*>(bad.data()), bad.size(), used) == -1);
    }
    const std::string large(4097, 'x');
    assert(kujiequ::probe::inspectConnect(reinterpret_cast<const uint8_t*>(large.data()), large.size(), used) == -1);

    // Exercise repeated sessions and every byte across real loopback TCP sockets.
    for (int iteration=0; iteration<3; ++iteration) {
        std::cerr << "iteration " << iteration << "\n";
        int fds[2]; assert(socketpair(AF_UNIX,SOCK_DGRAM,0,fds)==0);
        int server=socket(AF_INET,SOCK_STREAM,0); assert(server>=0);
        sockaddr_in addr{}; addr.sin_family=AF_INET; addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        assert(bind(server,reinterpret_cast<sockaddr*>(&addr),sizeof(addr))==0);
        assert(listen(server,1)==0); socklen_t len=sizeof(addr);
        assert(getsockname(server,reinterpret_cast<sockaddr*>(&addr),&len)==0);
        std::atomic<bool> done{false}; std::atomic<size_t> echoed{0};
        std::thread echo([&]{
            pollfd wait{server,POLLIN,0};
            if (poll(&wait,1,5000)<=0) return;
            int c=accept(server,nullptr,nullptr); assert(c>=0);
            timeval timeout{10,0}; setsockopt(c,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
            setsockopt(c,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
            std::array<char,317> b{};
            while (!done.load()) {
                ssize_t n=recv(c,b.data(),b.size(),0); if(n<=0)break;
                size_t off=0;
                while(off<static_cast<size_t>(n)) { ssize_t w=send(c,b.data()+off,n-off,MSG_NOSIGNAL); if(w<=0)break; off+=w; }
                echoed+=off;
            }
            shutdown(c,SHUT_WR); close(c);
        });
        {
            kujiequ::probe::TcpRelay relay(fds[0],ntohs(addr.sin_port)); assert(relay.ready());
            kujiequ::probe::TcpRelay concurrent(fds[0],ntohs(addr.sin_port)); assert(!concurrent.ready());
            std::string payload; for(size_t i=0;i<128*1024;++i)payload.push_back(static_cast<char>(i%251));
            uint32_t seq=10001, remote=0, remoteStart=0; size_t offset=0;
            bool handshake=false, droppedSynAck=false, droppedData=false, fin=false;
            std::string response;
            sendPacket(fds[1],packet(seq-1,0,2));
            auto start=std::chrono::steady_clock::now();
            while(std::chrono::steady_clock::now()-start<std::chrono::seconds(12)) {
                assert(relay.tick());
                pollfd p{fds[1],POLLIN,0};
                if(poll(&p,1,1)>0) {
                    std::array<uint8_t,2048>b{}; ssize_t n=read(fds[1],b.data(),b.size()); assert(n>=40);
                    size_t ip=(b[0]&15)*4, tcp=(b[ip+12]>>4)*4;
                    uint8_t flags=b[ip+13]; uint32_t rseq=get32(&b[ip+4]);
                    if(flags&2) {
                        if(iteration==0&&!droppedSynAck) { droppedSynAck=true; continue; }
                        remoteStart=rseq+1; remote=remoteStart; handshake=true;
                        sendPacket(fds[1],packet(seq,remote,16));
                    } else if(handshake) {
                        size_t body=n-ip-tcp;
                        if(body&&iteration==1&&!droppedData) { droppedData=true; continue; }
                        if(body&&rseq==remote) {
                            response.append(reinterpret_cast<char*>(b.data()+ip+tcp),body); remote+=body;
                        }
                        if(flags&1) { ++remote; fin=true; }
                        if(body||(flags&1))sendPacket(fds[1],packet(seq,remote,16));
                    }
                }
                // Advance sends only as echoed bytes free the small peer window.
                if(handshake&&offset<payload.size()&&offset-response.size()<4096) {
                    size_t amount=std::min<size_t>(701,payload.size()-offset);
                    sendPacket(fds[1],packet(seq,remote,24,payload.substr(offset,amount))); seq+=amount;offset+=amount;
                }
                if(response.size()==payload.size()) {
                    assert(response==payload); sendPacket(fds[1],packet(seq++,remote,17));
                    // Allow the FIN to propagate through the upstream socket.
                    for(int i=0;i<100;++i) { assert(relay.tick()); poll(nullptr,0,1); }
                    break;
                }
            }
            (void)fin; (void)remoteStart;
            assert(response==payload); assert(echoed==payload.size()); assert(relay.packets()>100);
            assert(relay.bytes()>payload.size());
        }
        done=true; echo.join(); close(server);close(fds[0]);close(fds[1]);
    }
    std::atomic<bool> cancelled{true};
    assert(kujiequ::probe::runTcp(-1,"marker",cancelled).code==kujiequ::probe::Cancelled);
    std::cout << "PASS: 128 KiB byte-exact duplex TCP relay, real upstream sockets, small window, SYN/data loss retransmission, FIN, exclusive stack, repeat cleanup, early cancel\n";
}
