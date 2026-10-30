#!/usr/bin/env python3
"""
Unit and regression test suite for gemini_board_budget.
Verifies all mathematical bounds, data integrity, invariants, and JSON structure.
Uses standard library unittest.
"""

import json
import unittest
from pathlib import Path
import sys

# Ensure tasks/gemini_board_budget is on sys.path
TASK_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TASK_DIR))

from budget import build_budget

class TestBoardBudget(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = build_budget()

    def test_manifest_mac_counts(self):
        mv = self.data["manifest_verification"]
        self.assertEqual(mv["useful_mac"], 3461011968, f"Useful MACs mismatch: {mv['useful_mac']}")
        self.assertEqual(mv["padded_mac"], 3991404544, f"Padded MACs mismatch: {mv['padded_mac']}")
        self.assertEqual(mv["unique_c_outputs"], 4471808, f"Unique C outputs mismatch: {mv['unique_c_outputs']}")
        self.assertEqual(mv["total_tiles"], 121808, f"Tile count mismatch: {mv['total_tiles']}")
        ratio = mv["padded_mac"] / mv["useful_mac"]
        self.assertTrue(1.15 < ratio < 1.16, f"Padding ratio expected ~1.153, got {ratio}")

    def test_tensor_compulsory_bounds(self):
        tf = self.data["tensor_footprint_compulsory_bounds"]
        self.assertEqual(tf["unique_weight_bytes"], 81007616)
        self.assertEqual(tf["boundary_input_bytes"], 4539392)
        self.assertEqual(tf["boundary_output_bytes"], 16508928)
        self.assertEqual(tf["unique_tensor_range_bytes"], 12592128)
        self.assertEqual(tf["compulsory_onchip_intermediate_lb_bytes"], 102055936)
        self.assertEqual(tf["all_intermediate_ddr_coarse_lb_bytes"], 127240192)
        
        # Invariants
        self.assertLess(tf["compulsory_onchip_intermediate_lb_bytes"], tf["all_intermediate_ddr_coarse_lb_bytes"])
        self.assertLess(tf["all_intermediate_ddr_coarse_lb_bytes"], tf["actual_measured_68plan_bytes"])
        self.assertGreater(tf["traffic_amplification_vs_onchip_lb"], 9.0)
        self.assertGreater(tf["vector_traffic_amplification_vs_tensor_footprint"], 60.0)

    def test_read_write_decomposition(self):
        rw = self.data["read_write_decomposition"]
        self.assertEqual(rw["read_bytes"], 577473808)
        self.assertEqual(rw["write_bytes"], 355555088)
        self.assertEqual(rw["sum_bytes"], 933028896)
        self.assertAlmostEqual(rw["read_ratio"] + rw["write_ratio"], 1.0, places=4)

    def test_compute_frequencies_monotonicity(self):
        cf = self.data["compute_frequency_scenarios"]
        prev_useful = float("inf")
        for row in cf:
            self.assertLess(row["useful_matrix_lb_s"], prev_useful)
            prev_useful = row["useful_matrix_lb_s"]
            self.assertGreater(row["padded_matrix_lb_s"], row["useful_matrix_lb_s"])

    def test_systolic_bandwidth_matching_formula(self):
        pe_eval = self.data["pe_systolic_bandwidth_matching"]
        for tile_res in pe_eval:
            M, N, K = tile_res["shape"]
            expected_d = M * K * 2 + K * N * 1 + M * N * 6
            self.assertEqual(tile_res["total_bytes"], expected_d)
            expected_macs = M * N * K
            self.assertEqual(tile_res["macs"], expected_macs)
            expected_intensity = expected_macs / expected_d
            self.assertAlmostEqual(tile_res["intensity_mac_per_b"], expected_intensity, places=3)
            self.assertAlmostEqual(tile_res["intensity_ops_per_b"], 2 * expected_intensity, places=3)

            for config in tile_res["configurations"]:
                bw = config["bandwidth_GB_s"] * 1e9
                fc = config["compute_MHz"] * 1e6
                expected_p_equiv = (bw * expected_intensity) / fc
                self.assertAlmostEqual(config["bandwidth_supported_P_equiv"], expected_p_equiv, delta=0.1)
                for p_key, p_stat in config["pe_utilization"].items():
                    p_val = int(p_key.replace("PE", ""))
                    expected_util = min(1.0, expected_p_equiv / p_val)
                    self.assertAlmostEqual(p_stat["utilization"], expected_util, places=3)

    def test_systolic_array_internal_feeding(self):
        arrays = self.data["systolic_array_internal_feeding"]
        for arr in arrays:
            r = arr["rows_R"]
            c = arr["cols_C"]
            p = arr["pe_count"]
            self.assertEqual(r * c, p)
            expected_feed = 2 * r + c
            self.assertEqual(arr["internal_boundary_feed_bytes_per_cycle"], expected_feed)
            self.assertEqual(arr["internal_boundary_feed_bits_per_cycle"], expected_feed * 8)

    def test_budget_json_generation(self):
        budget_json = TASK_DIR / "budget.json"
        self.assertTrue(budget_json.exists(), "budget.json does not exist")
        content = json.loads(budget_json.read_text(encoding="utf-8"))
        self.assertIn("metadata", content)
        self.assertIn("manifest_verification", content)
        self.assertIn("tensor_footprint_compulsory_bounds", content)
        self.assertIn("discrepancy_reconciliation", content)
        self.assertIn("actionable_priority_roadmap", content)

if __name__ == "__main__":
    unittest.main()
