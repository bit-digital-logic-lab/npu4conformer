"""Read-only V4 UART telemetry. Sends no commands and never toggles DTR."""
import argparse
import json
from pathlib import Path
import struct
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'host'))
from frozen_imports import require_frozen_modules
WindowsSerial = require_frozen_modules()[0].WindowsSerial


def decode(frame):
    flags, speed, phy, status, rx, tx, bad, fcs, overflow, underflow, arp, reserved = struct.unpack('<BBIHIIHHHHHH', frame[4:])
    return dict(config_done=bool(flags & 1), config_error=bool(flags & 2),
                engine_busy=bool(flags & 4), rx_delay_ready=bool(flags & 8),
                speed={0: '10M', 1: '100M', 2: '1G'}.get(speed, str(speed)),
                phy_id=f'{phy:08x}', basic_status=f'{status:04x}', udp_received=rx,
                udp_transmitted=tx, bad_frames=bad, bad_fcs=fcs, overflow=overflow,
                underflow=underflow, arp_failures=arp)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', default='COM8')
    p.add_argument('--seconds', type=float, default=5)
    args = p.parse_args()
    if not 0 < args.seconds <= 60:
        p.error('seconds must be in (0, 60]')
    stream = WindowsSerial(args.port, 921600, timeout=0.2)
    pending = bytearray()
    count = 0
    end = time.monotonic() + args.seconds
    try:
        while time.monotonic() < end:
            pending.extend(stream.read(128))
            while len(pending) >= 32:
                offset = pending.find(b'V4DG')
                if offset < 0:
                    del pending[:-3]
                    break
                if offset:
                    del pending[:offset]
                if len(pending) < 32:
                    break
                print(json.dumps(decode(pending[:32])), flush=True)
                del pending[:32]
                count += 1
    finally:
        stream.close()
    if not count:
        raise SystemExit('No complete V4DG telemetry frames received')


if __name__ == '__main__':
    main()
