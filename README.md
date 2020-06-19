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

# Contributing

This BOSH release was forked from the `strongswan-boshrelease`,
which was mostly unused (and a bit out-of-date), but was aimed at
solving a _different_ problem with strongSwan -- that of VPN
tunnel configuration.

Contributions to this BOSH release are welcome!  If you find a
bug, or something doesn't work quite right, please open an issue
in the GitHub issue tracker.


[1]: https://strongswan.org/
