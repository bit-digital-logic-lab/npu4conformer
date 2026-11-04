"""随机特征数值测试包的只读加载与完整性检查；不执行 ZIP 内的代码。"""
from __future__ import annotations

from collections import Counter
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile

import numpy as np

_ROOT = "random200_v1/"
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_INPUT_KEYS = {"feats", "tokens"}
_OUTPUT_KEYS = {"encoder_memory", "encoder_memory_lengths", "ctc_log_probs", "decoder_log_probs"}
_MAX_MEMBER_BYTES = 32 * 1024 * 1024
_MAX_ARCHIVE_BYTES = 512 * 1024 * 1024


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _integer(value, name, minimum=0, maximum=1_000_000):
    _require(type(value) is int and minimum <= value <= maximum, f"{name}: 非法整数")
    return value


def _digest(raw):
    return hashlib.sha256(raw).hexdigest()


def _hash_check(raw, expected, name):
    _require(isinstance(expected, str) and _SHA256.fullmatch(expected), f"{name}: SHA256 格式错误")
    _require(_digest(raw) == expected, f"{name}: SHA256 不匹配")


def _safe_path(name):
    # 不解压文件，但仍拒绝越界路径、Windows 盘符和重复斜杠，避免后续误用。
    _require(isinstance(name, str) and name and "\\" not in name and ":" not in name,
             f"非法 ZIP 路径: {name!r}")
    p = PurePosixPath(name)
    _require(not p.is_absolute() and all(x not in ("", ".", "..") for x in name.rstrip("/").split("/")),
             f"非法 ZIP 路径: {name!r}")
    return name


def _json(raw, name):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            _require(key not in result, f"{name}: 重复 JSON key {key}")
            result[key] = value
        return result
    def bad_constant(value):
        raise ValueError(f"{name}: 非有限 JSON 数值 {value}")
    try:
        value = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=unique, parse_constant=bad_constant)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{name}: 无效 JSON") from exc
    _require(isinstance(value, dict), f"{name}: 需要 JSON 对象")
    return value


def _array_archive(raw, name, expected_keys=None):
    # NPY 文件不得包含 object/pickle；同时限制内部声明大小，避免压缩炸弹。
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as nested:
            infos = nested.infolist()
            _require(len(infos) == len({i.filename for i in infos}), f"{name}: 重复 NPZ 项")
            _require(sum(i.file_size for i in infos) <= _MAX_MEMBER_BYTES, f"{name}: NPZ 过大")
            for item in infos:
                _safe_path(item.filename)
                _require(item.filename.endswith(".npy") and "/" not in item.filename,
                         f"{name}: 非法 NPZ 项")
                # 先读 NPY 头并核对实际字节数，防止小文件声明巨大数组导致异常分配。
                with nested.open(item) as handle:
                    version = np.lib.format.read_magic(handle)
                    _require(version in ((1, 0), (2, 0)), f"{name}: 不支持的 NPY 版本")
                    reader = (np.lib.format.read_array_header_1_0 if version == (1, 0)
                              else np.lib.format.read_array_header_2_0)
                    shape, _, dtype = reader(handle)
                    _require(dtype.kind in "fiu" and not dtype.hasobject, f"{name}: 非法 NPY dtype")
                    _require(len(shape) <= 5 and all(type(v) is int and v >= 0 for v in shape),
                             f"{name}: 非法 NPY shape")
                    count = 1
                    for dimension in shape:
                        count *= dimension
                        _require(count * dtype.itemsize <= _MAX_MEMBER_BYTES, f"{name}: NPY 声明过大")
                    _require(handle.tell() + count * dtype.itemsize == item.file_size,
                             f"{name}: NPY 数据长度不匹配")
        with np.load(io.BytesIO(raw), allow_pickle=False) as loaded:
            if expected_keys is not None:
                _require(set(loaded.files) == expected_keys, f"{name}: 张量 keys 不匹配")
            arrays = {k: loaded[k] for k in loaded.files}
        for key, array in arrays.items():
            _require(array.dtype.kind in "fiu" and np.isfinite(array).all(), f"{name}/{key}: 非有限或非法 dtype")
        return arrays
    except (zipfile.BadZipFile, KeyError, OSError, TypeError) as exc:
        raise ValueError(f"{name}: 无效 NPZ") from exc


class RandomVectorDataset:
    """完整验证 random200_v1.zip，再按 case 读取新数组。

    默认强制 200 组，expected_case_count 仅用于显式的小型格式单元测试。
    初始化检查所有数据，而非只抽查；load_case 再核验该组文件，防止读入期间被替换。
    metadata/report 返回副本，调用方不能修改内部校验依据。
    """

    def __init__(self, zip_path, *, expected_case_count=200):
        self.zip_path = Path(zip_path).resolve()
        _integer(expected_case_count, "expected_case_count", 1, 10000)
        self._stamp = self._file_stamp()
        with self.zip_path.open("rb") as handle:
            archive_sha256 = hashlib.file_digest(handle, "sha256").hexdigest()
        self._cases = {}
        self._metadata = {}
        self._report = {}
        try:
            with zipfile.ZipFile(self.zip_path) as archive:
                allowed = self._validate_inventory(archive)
                dataset_raw = archive.read(_ROOT + "dataset.json")
                index_raw = archive.read(_ROOT + "cases.jsonl")
                generation = _json(archive.read(_ROOT + "generation_report.json"), "generation_report.json")
                _hash_check(dataset_raw, generation.get("dataset_sha256"), "dataset.json")
                _hash_check(index_raw, generation.get("cases_index_sha256"), "cases.jsonl")
                metadata = _json(dataset_raw, "dataset.json")
                _require(metadata.get("format_version") == 1 and type(metadata.get("format_version")) is int,
                         "不支持的 format_version")
                _require(type(metadata.get("case_count")) is int and metadata["case_count"] == expected_case_count,
                         "case_count 与预期不一致")
                for field, value in (("feature_dim", 80), ("vocab_size", 5000), ("sos_id", 4999)):
                    _require(type(metadata.get(field)) is int and metadata[field] == value, f"{field} 与 Model A 不匹配")
                _require(metadata.get("output_keys") == ["encoder_memory", "encoder_memory_lengths", "ctc_log_probs", "decoder_log_probs"],
                         "output_keys 与协议不匹配")
                _require(metadata.get("feature_space") == "normalized" and metadata.get("random_distribution") == "uniform",
                         "不支持的随机特征生成方案")
                _require(metadata.get("normalization") == "feats=effective_ONNX_feature_mean+effective_ONNX_feature_std*U(low,high)"
                         and metadata.get("low") == -2.0 and metadata.get("high") == 2.0
                         and metadata.get("prng") == "numpy.Generator(PCG64(SeedSequence([seed,case_index])))",
                         "归一化或随机数生成语义与协议不匹配")
                _integer(metadata.get("seed"), "seed", 0, 2**32 - 1)
                _require(metadata.get("feature_wire_scale") is None and metadata.get("feature_wire_zero_point") == 0,
                         "输入不是已支持的 FP32 特征协议")
                _require(generation.get("status") == "completed" and generation.get("completed") == expected_case_count
                         and generation.get("requested") == expected_case_count, "数据生成记录不完整")
                _require(generation.get("real_model_inference_completed") is True and generation.get("fpga_executed") is False,
                         "数据生成范围与软件数值测试协议不一致")
                index = [_json(line, "cases.jsonl") for line in index_raw.splitlines() if line.strip()]
                _require(len(index) == expected_case_count, "cases.jsonl 数量不匹配")
                specifications = metadata.get("specifications")
                _require(isinstance(specifications, list) and len(specifications) == expected_case_count,
                         "specifications 数量不匹配")
                companions = metadata.get("companion_files_sha256")
                _require(isinstance(companions, dict) and set(companions) == {"graph_quantization.json", "quantization_parameters.npz"},
                         "companion 文件集合不匹配")
                for name, checksum in companions.items():
                    _hash_check(archive.read(_ROOT + name), checksum, name)
                graph = _json(archive.read(_ROOT + "graph_quantization.json"), "graph_quantization.json")
                _require(graph.get("parameter_values_file") == "quantization_parameters.npz"
                         and graph.get("parameter_values_sha256") == companions["quantization_parameters.npz"],
                         "图量化参数关联不一致")
                params = _array_archive(archive.read(_ROOT + "quantization_parameters.npz"), "quantization_parameters.npz")
                graph_summary = self._validate_graph(graph, params, metadata)
                fingerprints = set()
                shapes = Counter()
                for number, (entry, spec) in enumerate(zip(index, specifications)):
                    case_id = f"case_{number:04d}"
                    _require(entry.get("case_id") == case_id and entry.get("case_file") == f"cases/{case_id}/case.json",
                             "case 索引顺序、ID 或路径非法")
                    _require(isinstance(spec, dict) and spec.get("case_id") == case_id
                             and type(spec.get("case_index")) is int and spec["case_index"] == number,
                             "specifications 顺序或 ID 不一致")
                    raw = archive.read(_ROOT + entry["case_file"])
                    _hash_check(raw, entry.get("case_sha256"), entry["case_file"])
                    case = _json(raw, entry["case_file"])
                    for field in ("case_id", "case_index", "feature_frames", "prefix_length"):
                        _require(case.get(field) == spec.get(field), f"{case_id}: {field} 与规格不一致")
                    _integer(case.get("case_index"), "case_index")
                    frames = _integer(case.get("feature_frames"), "feature_frames", 7, 4096)
                    prefix = _integer(case.get("prefix_length"), "prefix_length", 1, 4096)
                    _require(case.get("seed_entropy") == [metadata.get("seed"), number], f"{case_id}: seed_entropy 不一致")
                    self._cases[case_id] = case
                    inputs, _ = self._read_case(archive, case_id)
                    fingerprint = _digest(inputs["feats"].tobytes() + inputs["tokens"].tobytes())
                    _require(fingerprint not in fingerprints, "重复随机输入")
                    fingerprints.add(fingerprint)
                    shapes[(frames, prefix)] += 1
                expected_files = {_ROOT + x for x in ("dataset.json", "generation_report.json", "cases.jsonl", "graph_quantization.json", "quantization_parameters.npz")}
                for case_id in self._cases:
                    expected_files.update(_ROOT + f"cases/{case_id}/{name}" for name in ("case.json", "inputs.npz", "inputs.bin", "expected.npz", "expected.bin"))
                _require(allowed == expected_files, "ZIP 包有未声明或缺失文件")
                self.case_ids = tuple(self._cases)
                self._metadata = metadata
                self._report = {
                    "schema_version": 1, "archive": str(self.zip_path), "archive_sha256": archive_sha256,
                    "zip_sha256": archive_sha256,
                    "archive_bytes": self._stamp[0], "dataset_sha256": _digest(dataset_raw),
                    "cases_index_sha256": _digest(index_raw), "companion_files_sha256": companions,
                    "case_count": expected_case_count, "verified_tensor_count": expected_case_count * 6,
                    "verified_case_payload_file_count": expected_case_count * 4,
                    "verified_case_metadata_file_count": expected_case_count,
                    "all_hashes_match": True, "npz_binary_identical": True, "all_tensors_finite": True,
                    "duplicate_inputs": 0, "audio_file_count": 0, "reference_transcription_count": 0,
                    "wer_applicable": False, "sample_rate": None,
                    "shape_distribution": [{"feature_frames": a, "prefix_length": b, "count": n} for (a, b), n in shapes.items()],
                    "generation_claims": generation,
                    "source_models": metadata.get("onnx_models"), "source_models_in_archive": False,
                    "source_model_hashes_independently_verified": False,
                    "graph_quantization": graph_summary,
                    "feature_semantics": "FP32 feats = external effective ONNX mean + std * uniform(-2,2); run current model normalization before encoder",
                    "quantization_difference": "External reference quantizes weights and activations with INT16 Q/DQ; this project quantizes selected weights only and runs FP32 operators",
                    "scope": "Synthetic feature encoder, CTC and one decoder next-token distribution; no waveform frontend, beam search, WER or hardware execution",
                }
            _require(self._file_stamp() == self._stamp, "ZIP 在校验过程中发生变化")
        except (zipfile.BadZipFile, KeyError, OSError) as exc:
            raise ValueError(f"随机测试包不完整或损坏: {exc}") from exc

    def _file_stamp(self):
        info = self.zip_path.stat()
        return info.st_size, info.st_mtime_ns

    @property
    def metadata(self):
        return deepcopy(self._metadata)

    @property
    def report(self):
        return deepcopy(self._report)

    @staticmethod
    def _validate_inventory(archive):
        infos = archive.infolist()
        names = set()
        files = set()
        _require(sum(i.file_size for i in infos) <= _MAX_ARCHIVE_BYTES, "ZIP 解压声明总量过大")
        for item in infos:
            name = _safe_path(item.filename)
            _require(name.startswith(_ROOT), "ZIP 文件不在 random200_v1 根目录内")
            # Windows 文件系统忽略大小写，大小写别名同样视作冲突。
            _require(name.casefold() not in names, "重复 ZIP 项")
            names.add(name.casefold())
            _require(not (item.flag_bits & 1), "不接受加密 ZIP")
            _require(not stat.S_ISLNK(item.external_attr >> 16), "不接受 ZIP 符号链接")
            _require(item.file_size <= _MAX_MEMBER_BYTES, "ZIP 单文件过大")
            if not item.is_dir():
                files.add(name)
        return files

    @staticmethod
    def _validate_graph(graph, params, metadata):
        graphs = graph.get("graphs")
        _require(isinstance(graphs, dict) and set(graphs) == {"encoder", "ctc", "decoder"}, "量化图集合不匹配")
        result = {}
        source_models = metadata.get("onnx_models")
        _require(isinstance(source_models, dict) and set(source_models) == set(graphs), "来源模型声明不匹配")
        for name, model in graphs.items():
            _require(isinstance(model, dict) and isinstance(source_models[name], dict)
                     and isinstance(model.get("sha256"), str) and _SHA256.fullmatch(model["sha256"])
                     and model["sha256"] == source_models[name].get("sha256"), "来源模型哈希声明不一致")
            nodes = model.get("qdq_nodes")
            _require(isinstance(nodes, list) and nodes, "缺少 QDQ 节点元数据")
            count = 0
            for node in nodes:
                _require(node.get("op_type") in ("QuantizeLinear", "DequantizeLinear") and node.get("quantized_dtype") == "int16", "QDQ 节点不是 INT16")
                scale = params.get(node.get("scale_key"))
                zero = params.get(node.get("zero_point_key"))
                _require(scale is not None and scale.dtype == np.dtype("float32") and np.all(scale > 0), "QDQ scale 非法")
                _require(zero is not None and zero.dtype == np.dtype("int16"), "QDQ zero_point 非法")
                _require(scale.shape == zero.shape, "QDQ scale/zero_point 形状不一致")
                count += node["op_type"] == "QuantizeLinear"
            _require(model.get("activation_q_nodes") == count, "activation_q_nodes 计数不一致")
            result[name] = {"activation_quantize_nodes": count, "qdq_node_count": len(nodes), "declared_onnx_sha256": model["sha256"]}
        return result

    def _read_case(self, archive, case_id):
        case = self._cases[case_id]
        frames, prefix = case["feature_frames"], case["prefix_length"]
        encoded = (frames - 3) // 4  # Model A 两层 kernel=3、stride=2 的无 padding 子采样。
        expected_shapes = {
            "feats": ((1, frames, 80), "<f4"), "tokens": ((1, prefix), "<i8"),
            "encoder_memory": ((1, encoded, 512), "<f4"), "encoder_memory_lengths": ((1,), "<i8"),
            "ctc_log_probs": ((1, encoded, 5000), "<f4"), "decoder_log_probs": ((1, 5000), "<f4"),
        }
        result = []
        for group, keys in (("inputs", _INPUT_KEYS), ("expected", _OUTPUT_KEYS)):
            descriptor = case.get(group)
            _require(isinstance(descriptor, dict) and set(descriptor) == {"npz", "npz_sha256", "binary", "binary_sha256", "binary_bytes", "packing", "tensors"},
                     f"{case_id}/{group}: 文件描述字段非法")
            _require(descriptor["npz"] == group + ".npz" and descriptor["binary"] == group + ".bin", "case 文件名不匹配")
            _require(descriptor["packing"] == "C-order, little-endian, concatenated, no padding", "不支持的打包规则")
            base = _ROOT + f"cases/{case_id}/"
            npz = archive.read(base + descriptor["npz"])
            binary = archive.read(base + descriptor["binary"])
            _hash_check(npz, descriptor["npz_sha256"], base + descriptor["npz"])
            _hash_check(binary, descriptor["binary_sha256"], base + descriptor["binary"])
            _require(type(descriptor["binary_bytes"]) is int and len(binary) == descriptor["binary_bytes"], "BIN 文件长度不匹配")
            arrays = _array_archive(npz, base + descriptor["npz"], keys)
            tensors = descriptor["tensors"]
            _require(isinstance(tensors, list) and len(tensors) == len(keys), "张量描述数量不匹配")
            seen = set()
            offset = 0
            for tensor in tensors:
                _require(isinstance(tensor, dict) and set(tensor) == {"key", "shape", "dtype", "logical_dtype", "order", "byte_order", "offset_bytes", "nbytes", "elements", "element_bytes", "tensor_sha256"},
                         "张量描述字段非法")
                key = tensor["key"]
                _require(isinstance(key, str) and key in keys and key not in seen, "张量描述 key 重复或非法")
                seen.add(key)
                array = arrays[key]
                shape, dtype = expected_shapes[key]
                _require(array.shape == shape and array.dtype.str == dtype, f"{key}: shape/dtype 不匹配")
                _require(tensor["shape"] == list(shape) and all(type(v) is int for v in tensor["shape"])
                         and tensor["dtype"] == dtype and tensor["logical_dtype"] == array.dtype.name,
                         f"{key}: 声明 shape/dtype 不匹配")
                _require(tensor["order"] == "C" and tensor["byte_order"] == "little", "只支持 C-order little-endian")
                for field, value in (("offset_bytes", offset), ("nbytes", array.nbytes), ("elements", array.size), ("element_bytes", array.itemsize)):
                    _require(type(tensor[field]) is int and tensor[field] == value, f"{key}: {field} 不匹配")
                raw = array.tobytes(order="C")
                _hash_check(raw, tensor["tensor_sha256"], key)
                _require(binary[offset:offset + array.nbytes] == raw, f"{key}: NPZ/BIN 不一致")
                offset += array.nbytes
            _require(offset == len(binary), "BIN 有尾部额外字节")
            result.append(arrays)
        inputs, expected = result
        _require(int(inputs["tokens"][0, 0]) == 4999, "tokens 首项必须为 SOS=4999")
        _require(np.all((inputs["tokens"] >= 0) & (inputs["tokens"] < 5000)), "tokens 超出词表范围")
        _require(int(expected["encoder_memory_lengths"][0]) == encoded, "encoder_memory_lengths 不匹配")
        return inputs, expected

    def load_case(self, case_id):
        """返回 (inputs, expected) 新数组；不把外部期望值回填为本次模型输出。"""
        _require(case_id in self._cases, f"未知 case_id: {case_id}")
        _require(self._file_stamp() == self._stamp, "ZIP 自初始化后发生变化")
        try:
            with zipfile.ZipFile(self.zip_path) as archive:
                return self._read_case(archive, case_id)
        except (zipfile.BadZipFile, KeyError, OSError) as exc:
            raise ValueError(f"随机测试包读取失败: {exc}") from exc
