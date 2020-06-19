# IPsec for BOSH

This BOSH release leverages [strongSwan][1] to provide IPsec/IKE
for securing network traffic on your BOSH VMs, at a layer _below_
the application.  This helps catch all those pesky cleartext
servers, systems that don't support TLS natively, etc.

## Getting Started

Unfortunately, IPsec isn't something you _just run_ - it requires
a non-trivial amount of information about the network topology,
who is and is not participating in IPsec, what X.509 authorities
are in force, and who has what certificate.

This repository ships with a simple manifest that spins up two VMs
with IPsec configured between them, if you can provide it with
networking information.  This can be used to validate this BOSH
release **before** you incorporate it into your infrastructure for
real.

    bosh deploy manifests/ipsec-demo.yml \
           -v network=default \
           -v first_ip=10.0.0.16 \
           -v second_ip=10.0.0.17

The two variables, `first_ip` and `second_ip` will be assigned to
the two nodes, so they will need to exist in your cloud config as
static ranges on the network you chose (via `network=...`).

Traffic between those two IP addresses will be encrypted.

To validate, you can initiate a connection (via something like
`nc`) between the hosts while running an appropriate `tcpdump` on
the link.  Here's an idea to get you started:

    vcap@node1 $ nc -l 4004

    vcap@node2 $ /bin/sh -c 'while true; do date; sleep 1; done' | \
                   nc 10.0.0.17 4004

Then, you can attempt to sniff traffic on port 4004, from either
node:

    vcap@node1 # tcpdump -Xnvv host ((first_ip))

If IPsec is functioning as expected, your `tcpdump` output should
_not_ contain readable date stamps (packet payloads).  Instead,
you should see IP packets with ESP markers and `spi` values in
them:

    20:42:41.010979 IP (tos 0x0, ttl 64, id 21002, offset 0, flags [DF], proto ESP (50), length 88)
    10.128.16.132 > 10.128.16.133: ESP(spi=0xc5f84573,seq=0x84d), length 68
        0x0000:  4500 0058 520a 4000 4032 b261 0a80 1084  E..XR.@.@2.a....
        0x0010:  0a80 1085 c5f8 4573 0000 084d 5575 4029  ......Es...MUu@)
        0x0020:  4479 f025 2b18 b6ec 3f2b b7e5 e523 8c21  Dy.%+...?+...#.!
        0x0030:  32cd a59d a9df 2100 4eaf 4b02 fcfa a3ed  2.....!.N.K.....
        0x0040:  0a35 8676 6add 1087 1647 4663 e9b7 1cb1  .5.vj....GFc....
        0x0050:  5e0f 2fe2 7c84 2f4f                      ^./.|./O

If you want to see what a multi-zone setup looks like, where
different X.509 Certificate Authorities are setup, with
overlapping, but not harmonious trust boundaries, try spinning
`manifests/ipsec-demo-3-nodes.yml`, which takes three hosts and
puts them into two zones; the first VM will be able to talk
(encrypted) with the second and third VMs, but those two will only
talk to each other in the clear.  The manifest is worth study,
since it shows off multiple keypairs, as well as more than one
encrypted peer host/net.

Finally, if you're not happy with the default aes128gcm16 / sha256
/ modp2048 encrypyion / integrity / dh algorithm, you might want
to check out `manifests/ipsec-demo-aes256gcm16.yml`, to see how
you can set the `ike` and `esp` options on a per-endpoint basis,
and amp up that security!

# Troubleshooting

This release, especially when configured indiscriminantly as a
BOSH add-on, has the potential to disrupt low-level network
communications that are often thought of as "infallible".  Most of
the time, this presents as packets simply not making it to some
destination or other, pings timing out, etc.  In several cases,
you may start to get the sneaking suspicion that someone has put
in an iptables rule that is `-j DROP`-ing you.

When you get to that point, you'll want to get on-box somehow
(here's hoping `bosh ssh` still works for you!) and poke around.
To help you out, this BOSH release comes with a small `envrc` that
will put the strongSwan IPsec tools into your $PATH:

    source /var/vcap/jobs/ipsec/envrc

From there, you can take a look at the status of all known IPsec
connections on the box:

    bosh/vm $ ipsec statusall
    Status of IKE charon daemon (strongSwan 5.8.4, Linux 4.15.0-99-generic, x86_64):
      uptime: 47 seconds, since Jun 19 01:10:15 2020
      malloc: sbrk 1351680, mmap 0, used 245488, free 1106192
      worker threads: 11 of 16 idle, 5/0/0/0 working, job queue: 0/0/0/0, scheduled: 0
      loaded plugins: charon aes sha1 sha2 random nonce x509 revocation constraints pubkey pkcs1 pkcs7 pkcs8 pkcs12 pem gmp xcbc cmac hmac attr kernel-netlink socket-default stroke
    Listening IP addresses:
      10.128.16.132
    Connections:
    encrypted-host-10.128.16.133:  %any...10.128.16.133/32  IKEv1/2, dpddelay=10s
    encrypted-host-10.128.16.133:   local:  [CN=node1] uses public key authentication
    encrypted-host-10.128.16.133:    cert:  "CN=node1"
    encrypted-host-10.128.16.133:   remote: uses public key authentication
    encrypted-host-10.128.16.133:   child:  10.128.16.132/32 === 10.128.16.133/32 TRANSPORT, dpdaction=restart
    Routed Connections:
    encrypted-host-10.128.16.133{1}:  ROUTED, TRANSPORT, reqid 1
    encrypted-host-10.128.16.133{1}:   10.128.16.132/32 === 10.128.16.133/32
    Security Associations (0 up, 0 connecting):
      none

The `Security Associations` section will show connected and half-connected
peers.  When things break, you'll probably see lots of associations in the
"connecting" state, either because of firewalling, or because of bad
certificate / CA mismatch.

It can often be helpful to figure out what certificates are being
"seen" by the IPsec subsystem:

    bosh/vm $ ipsec listcerts

    List of X.509 End Entity Certificates

      subject:  "CN=node1"
      issuer:   "CN=IPSec Demo CA"
      validity:  not before Jun 19 00:46:35 2020, ok
                 not after  Jun 19 00:46:35 2021, ok (expires in 364 days)
      serial:    69:78:b1:71:f2:80:ee:41:59:b8:3f:23:8e:f4:31:70:78:9f:67:44
      altNames:  10.128.16.132
      flags:
      authkeyId: c0:ee:11:b9:8c:32:85:dc:80:1e:ef:20:ac:ac:99:f3:5f:92:c8:b0
      subjkeyId: e3:ba:46:12:4e:8f:02:3c:20:84:4d:95:e8:e9:68:33:5d:20:36:31
      pubkey:    RSA 2048 bits, has private key
      keyid:     2e:3c:d7:3d:96:27:fd:de:95:b0:b8:e7:b2:72:41:40:5c:a1:81:ec
      subjkey:   e3:ba:46:12:4e:8f:02:3c:20:84:4d:95:e8:e9:68:33:5d:20:36:31

If you want to verify the presence and wellformedness of configure
Certificate Authorities, you can run:

    $ ipsec listcacerts

    List of X.509 CA Certificates

      subject:  "CN=IPSec Demo CA"
      issuer:   "CN=IPSec Demo CA"
      validity:  not before Jun 19 00:46:33 2020, ok
                 not after  Jun 19 00:46:33 2021, ok (expires in 364 days)
      serial:    30:cb:5b:f4:9e:3f:4e:9e:77:14:31:8a:1d:e6:37:b8:a9:7a:35:75
      flags:     CA self-signed
      authkeyId: c0:ee:11:b9:8c:32:85:dc:80:1e:ef:20:ac:ac:99:f3:5f:92:c8:b0
      subjkeyId: c0:ee:11:b9:8c:32:85:dc:80:1e:ef:20:ac:ac:99:f3:5f:92:c8:b0
      pubkey:    RSA 2048 bits
      keyid:     68:2d:82:9a:96:fa:c1:02:d3:99:e0:4c:e5:29:49:41:fd:e3:49:f7
      subjkey:   c0:ee:11:b9:8c:32:85:dc:80:1e:ef:20:ac:ac:99:f3:5f:92:c8:b0

# Contributing

This BOSH release was forked from the `strongswan-boshrelease`,
which was mostly unused (and a bit out-of-date), but was aimed at
solving a _different_ problem with strongSwan -- that of VPN
tunnel configuration.

Contributions to this BOSH release are welcome!  If you find a
bug, or something doesn't work quite right, please open an issue
in the GitHub issue tracker.


[1]: https://strongswan.org/
