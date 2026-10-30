#!/usr/bin/env python3
import sys, random
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent / "candidate"))
from golden_pe import compute_pe_single, accumulate_c48

def generate_tile_vectors(filename, num_tiles=500, k_len=32):
    lines = []
    golden_tile_results = []
    random.seed(1234)

    a_corners = [-32768, -32767, -1, 0, 1, 32767, -256, 256, -16, 16]

    for tile in range(num_tiles):
        # Generate K pairs
        tile_sum = 0
        p0 = random.randint(0, 12)
        p1 = random.randint(0, 12)
        p2 = random.randint(0, 12)
        p3 = random.randint(0, 12)
        pos = p0 | (p1 << 4) | (p2 << 8) | (p3 << 12)
        clip = 1 if (tile % 2 == 1) else 0

        # Inject K cycles
        for k in range(k_len):
            if tile < len(a_corners):
                a = a_corners[tile]
            else:
                a = random.randint(-32768, 32767)
            w = random.randint(0, 127)

            prod = compute_pe_single(a, w, pos, clip)
            tile_sum = accumulate_c48(tile_sum, prod)

            # (a, w, pos, clip, av, wv, clear_sum, flush)
            lines.append((a & 0xFFFF, w, pos, clip, 1, 1, 0, 0))

        golden_tile_results.append(tile_sum)

        # Drain pipeline (5 bubble cycles: enough for both 3-cycle baseline and 4-cycle candidate)
        for _ in range(5):
            lines.append((0, 0, pos, clip, 0, 0, 0, 0))

        # Clear sum for next tile
        lines.append((0, 0, pos, clip, 0, 0, 1, 0))
        # 1 cycle idle after clear
        lines.append((0, 0, pos, clip, 0, 0, 0, 0))

    with open(filename, "w") as f:
        for item in lines:
            f.write(f"{item[0]:04x} {item[1]:02x} {item[2]:04x} {item[3]} {item[4]} {item[5]} {item[6]} {item[7]}\n")

    print(f"Generated {num_tiles} tiles ({len(lines)} total cycles) to {filename}")
    return lines, golden_tile_results

if __name__ == "__main__":
    generate_tile_vectors("bench/test_vectors_pe_tiles.txt", num_tiles=500, k_len=32)
