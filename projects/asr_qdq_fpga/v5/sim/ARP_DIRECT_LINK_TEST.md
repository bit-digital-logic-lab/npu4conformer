# Direct-link ARP regression

Run in PowerShell:

```powershell
& 'D:\fpga\fproject\adder_16\asr\v4\sim\run_arp_direct_link.ps1'
```

Observed result: **PASS, 11 checks**. The script compiles the existing, unchanged
`arp.v`, `arp_cache.v`, `arp_eth_rx.v`, `arp_eth_tx.v`, and `lfsr.v` with Icarus.
Only the simulation image under this directory is written. No serial/JTAG/socket
is opened and no bitstream is generated or downloaded.

The independent testbench drives complete Ethernet ARP headers and byte-stream
payloads; it decodes emitted ARP frames and checks the public lookup response.
It does not force internal cache or route-selection signals.

Configuration: FPGA `169.254.35.4`, MAC `02:00:00:00:35:04`, mask `/16`; simulated
PC `169.254.147.66`, MAC `10:20:30:40:50:60`. The simulated MAC is a fixture, not
the physical PC's identity. ARP retry intervals are shortened for simulation.

The checks establish:

1. Old gateway `0.0.0.0`: even after learning the PC from a valid discovery
   request, a lookup for the PC actually emits ARP target `0.0.0.0` and fails
   after the configured two retries. A valid PC answer cannot satisfy that key.
2. Gateway anchored to the FPGA's local IP: the same lookup emits the PC's IP,
   accepts a valid PC ARP answer, and returns its MAC without any ARP failure.
3. A repeated lookup uses the learned cache and emits no additional ARP frame.
4. Same-subnet lower host boundary `169.254.0.1` resolves directly.
5. Same-subnet upper host boundary `169.254.255.254` resolves directly.
6. The vendored implementation treats `169.254.0.0` as a unicast lookup. This
   documents its routing behavior; it is not a recommendation to assign that IP.
7. Directed broadcast `169.254.255.255` returns the broadcast MAC without ARP.
8. Limited broadcast `255.255.255.255` likewise returns the broadcast MAC.
9. Upper adjacent subnet `169.255.147.66` seeks the configured anchor and times
   out instead of falsely succeeding.
10. Lower adjacent subnet `169.253.147.66` has the same bounded failure behavior.
11. An incoming ARP frame marked with an AXI error does not seed the cache; a
    subsequent valid response resolves it correctly.

All transmitted frames are checked under deterministic header/payload
backpressure, including protocol fields, sender addresses, and payload length.

The self-IP gateway is a **direct-link subnet anchor**, not an external router.
This regression verifies ARP logic and its parameter contract only. It does not
prove the board wrapper uses those parameters, physical RGMII timing, UDP
checksum correctness, host firewall behavior, or ASR numerical acceptance.
