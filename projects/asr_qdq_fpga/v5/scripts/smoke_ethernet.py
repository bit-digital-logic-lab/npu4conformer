"""Explicit opt-in Ethernet-only smoke/throughput test; no programming or NIC edits."""
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import traceback
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'host'))
from ethernet_transport import EthernetBackend, open_link, encode_packet, decode_packet


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--host', default='169.254.35.4')
    p.add_argument('--bind-ip', default='169.254.147.66')
    p.add_argument('--port', type=int, default=49152)
    p.add_argument('--timeout', type=float, default=3)
    p.add_argument('--retries', type=int, default=2)
    p.add_argument('--words', type=int, default=8192)
    p.add_argument('--rounds', type=int, default=4)
    p.add_argument('--out', type=Path)
    p.add_argument('--allow-hardware', action='store_true')
    p.add_argument('--validate-only', action='store_true')
    args = p.parse_args(argv)
    if not 1 <= args.words <= 32768 or not 1 <= args.rounds <= 100:
        p.error('words must be 1..32768, rounds 1..100')
    if args.timeout <= 0 or not 0 <= args.retries <= 10:
        p.error('timeout must be positive, retries must be 0..10')
    if args.validate_only:
        assert decode_packet(encode_packet(1, 0, 0)) == (1, 0, 0, 0, b'')
        print(json.dumps(dict(pass_test=True, hardware_accessed=False, check='offline codec import')))
        return 0
    if not args.allow_hardware or args.out is None:
        p.error('--allow-hardware and fresh --out file are required for device access')
    destination = args.out.resolve()
    if (ROOT / 'reports').resolve() not in destination.parents or destination.exists():
        p.error('--out must be a fresh file inside v4/reports')
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = dict(started_utc=datetime.now(timezone.utc).isoformat(), pass_test=False,
                  data_arithmetic_pass=False, cleanup_confirmed=False, safe_for_followup_job=False,
                  hardware_access_attempted=False, hardware_accessed=False, handshake_complete=False,
                  hardware_access_semantics='True means HELLO/PING completed; null means attempted but not confirmed',
                  automatic_reopen_attempted=False,
                  scope='transport SRAM plus tiny V2 arithmetic smoke, not model golden',
                  fpga_endpoint=[args.host, args.port], bind_ip=args.bind_ip,
                  per_attempt_timeout_seconds=args.timeout, identical_packet_retries=args.retries,
                  source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    # Reserve this new report before touching the device. Never overwrite an old
    # report, including if another process created it after the exists() check.
    with destination.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)

    def save_result():
        temporary = destination.with_suffix(destination.suffix + '.writing')
        temporary.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
        os.replace(temporary, destination)

    backend = link = None
    started = time.perf_counter()
    try:
        result.update(hardware_access_attempted=True, hardware_accessed=None)
        save_result()
        link = open_link(args.host, args.port, local_host=args.bind_ip,
                         timeout=args.timeout, retries=args.retries,
                         deadline=started + 300)
        result.update(hardware_accessed=True, handshake_complete=True)
        backend = EthernetBackend(link)
        source = np.arange(args.words, dtype=np.uint32) * np.uint32(0x00100001)
        write_seconds = read_seconds = 0.0
        for iteration in range(args.rounds):
            pattern = source ^ np.uint32(0xa5a55a5a ^ iteration)
            before = time.perf_counter()
            backend.write_words(0, pattern)
            write_seconds += time.perf_counter() - before
            before = time.perf_counter()
            actual = backend.read_words(0, args.words)
            read_seconds += time.perf_counter() - before
            if not np.array_equal(actual, pattern):
                raise AssertionError(f'SRAM roundtrip differs in round {iteration}')
        byte_count = args.words * 4 * args.rounds
        result['roundtrip'] = dict(words=args.words, rounds=args.rounds, all_exact=True,
                                  write_seconds=write_seconds, read_seconds=read_seconds,
                                  write_payload_MBps=byte_count/max(write_seconds, 1e-12)/1e6,
                                  read_payload_MBps=byte_count/max(read_seconds, 1e-12)/1e6)
        # Explicitly simple independent expected constants, not an ASR oracle.
        aa = np.array([1.0, -2.0, 0.5, 0.0], dtype=np.float32)
        bb = np.array([2.0, 1.0, 0.25, -4.0], dtype=np.float32)
        wanted = np.array([3.0, -1.0, 0.75, -4.0], dtype=np.float32)
        summed = backend.binary('Add', aa, bb)
        if summed.tobytes() != wanted.tobytes():
            raise AssertionError('VEC Add smoke mismatch')
        ma = np.array([[1, -2, 3], [-4, 5, -6]], dtype=np.int16)
        mb = np.array([[7, -8], [9, 10], [-11, 12]], dtype=np.int16)
        wanted_mm = np.array([[-44, 8], [83, 10]], dtype=np.int64)
        actual_mm = backend.matmul_i16(ma, mb)
        if not np.array_equal(actual_mm, wanted_mm):
            raise AssertionError(f'MM_TILE smoke mismatch: {actual_mm.tolist()}')
        result.update(data_arithmetic_pass=True, vec_add_bit_exact=True, signed_int16_mm_exact=True)
    except BaseException as exc:
        result['error'] = f'{type(exc).__name__}: {exc}'
        traceback.print_exc()
    finally:
        if backend is not None:
            try:
                result['backend'] = backend.report()
            except BaseException as exc:
                result['report_error'] = f'{type(exc).__name__}: {exc}'
        try:
            if backend is not None:
                backend.close()
            elif link is not None:
                link.close()
        except BaseException as exc:
            result['cleanup_error'] = f'{type(exc).__name__}: {exc}'
        if link is not None:
            try:
                closed_state = link.report()
                result['ethernet_after_close'] = closed_state
                result['cleanup_confirmed'] = bool(
                    closed_state.get('closed') is True and closed_state.get('close_confirmed') is True
                    and closed_state.get('active') is False and closed_state.get('poisoned') is False
                    and 'cleanup_error' not in result)
            except BaseException as exc:
                result['cleanup_error'] = f'{type(exc).__name__}: {exc}'
        else:
            result['cleanup_note'] = ('open_link did not return a usable handle; HELLO may have reached FPGA; '
                                      'session closure unconfirmed, no automatic reopen or reset')
        result['pass_test'] = bool(result['data_arithmetic_pass'] and result['cleanup_confirmed']
                                   and not any(key in result for key in ('error', 'cleanup_error', 'report_error')))
        result['safe_for_followup_job'] = result['pass_test']
        if result['data_arithmetic_pass'] and not result['cleanup_confirmed']:
            result.setdefault('error', 'Data/arithmetic passed but session CLOSE is unconfirmed; do not start another job blindly')
        result.update(finished_utc=datetime.now(timezone.utc).isoformat(), elapsed_seconds=time.perf_counter()-started)
        save_result()
        print(json.dumps(result, indent=2))
    return 0 if result['pass_test'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
