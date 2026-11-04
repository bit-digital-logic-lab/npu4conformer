"""下载固定版本的模型和标准语音数据，并校验完整性。"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import tarfile
import time
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
MODEL_ID = "pyf98/librispeech_conformer"
MODEL_REVISION = "b74448c3b089eceea913735bd59a76d5252d8eec"
MODEL_ROOT = ROOT / "artifacts/pyf98_librispeech_conformer"
MODEL_FILES = {
    "meta.yaml": "c1f393187edcb3662fbc2621b8b990d2088b38c8ed28058b30814d5f7917ee86",
    "exp/asr_train_asr_conformer8_raw_en_bpe5000_sp/valid.acc.ave.pth": "8e94fe626aefaec3662a101cba7e112fd108de4871602c34852c27b09384b21b",
    "exp/asr_train_asr_conformer8_raw_en_bpe5000_sp/config.yaml": "add4f9af8dceb9c8dfaf01fdf385e178de352360e25b2a1d3f22591cf0a5f708",
    "data/en_token_list/bpe_unigram5000/bpe.model": "ec50979d91eb9f1cccff2c2e50371c89f24b7df19cf02902362cf4bcce640eb5",
    "exp/asr_stats_raw_en_bpe5000_sp/train/feats_stats.npz": "ec719c1ea25aee757c6df57352d6746ab944e26098e5e98555f56d8dc66a26e4",
}
DATA_MD5 = {"dev-clean": "42e2234ba48799c1f50f24a7926300a1", "test-clean": "32fa31d27d2e1cad72775fee3f4849a9"}


def file_hash(path: Path, algorithm: str = "sha256") -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, target: Path, expected: str | None, algorithm: str = "sha256") -> dict:
    """已有正确文件直接复用；仅对本工具的 .part 临时文件续传。"""
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if expected is not None and file_hash(target, algorithm) != expected:
            raise ValueError(f"已有文件校验不符，未覆盖: {target}")
        return {"path": str(target), "bytes": target.stat().st_size, "sha256": file_hash(target), "reused": True}
    partial = target.with_name(target.name + ".part")
    last_error = None
    for attempt in range(3):
        offset = partial.stat().st_size if partial.exists() else 0
        request = urllib.request.Request(url, headers={"User-Agent": "software4npu-asr-chip/0.1"})
        if offset:
            request.add_header("Range", f"bytes={offset}-")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                resumed = offset > 0 and response.status == 206
                if response.status == 206:
                    actual_range = response.headers.get("Content-Range", "")
                    if not actual_range.startswith(f"bytes {offset}-"):
                        raise ValueError(f"服务器续传范围不匹配: {actual_range}")
                count = offset if resumed else 0
                last_print = time.monotonic()
                with partial.open("ab" if resumed else "wb") as stream:
                    while block := response.read(1024 * 1024):
                        stream.write(block)
                        count += len(block)
                        if time.monotonic() - last_print > 15:
                            print(f"DOWNLOAD {target.name}: {count / 1e6:.1f} MB", flush=True)
                            last_print = time.monotonic()
            if expected is not None and file_hash(partial, algorithm) != expected:
                raise ValueError(f"下载校验不符，保留临时文件供检查: {partial}")
            partial.replace(target)
            print(f"VERIFIED {target.name}: {target.stat().st_size} bytes", flush=True)
            return {"path": str(target), "bytes": target.stat().st_size, "sha256": file_hash(target), "source_url": url, "reused": False}
        except ValueError:
            raise
        except Exception as exc:
            last_error = exc
            print(f"RETRY {target.name}: {type(exc).__name__}: {exc}", flush=True)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"下载失败: {url}") from last_error


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def prepare_model(model_root: Path = MODEL_ROOT) -> dict:
    rows = []
    for relative, digest in MODEL_FILES.items():
        url = f"https://huggingface.co/{MODEL_ID}/resolve/{MODEL_REVISION}/{relative}?download=true"
        row = download(url, model_root / relative, digest)
        row["relative_path"] = relative
        rows.append(row)
    card_url = f"https://huggingface.co/{MODEL_ID}/resolve/{MODEL_REVISION}/README.md?download=true"
    card = download(card_url, model_root / "README.md", None)
    report = {"schema_version": 1, "model_id": MODEL_ID, "revision": MODEL_REVISION, "files": rows, "model_card": card, "expected_license": "CC-BY-4.0"}
    write_json(model_root / "model_manifest.json", report)
    return report


def safe_extract(archive_path: Path, destination: Path) -> None:
    """拒绝路径越界和链接；只允许 LibriSpeech 下的普通文件和目录。"""
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "r:gz") as archive:
        members = archive.getmembers()
        for member in members:
            parts = Path(member.name).parts
            target = (destination / member.name).resolve()
            if (
                not parts
                or parts[0] != "LibriSpeech"
                or ".." in parts
                or chr(92) in member.name
                or ":" in member.name
                or not target.is_relative_to((destination / "LibriSpeech").resolve())
                or not (member.isfile() or member.isdir())
            ):
                raise ValueError(f"不允许的压缩包条目: {member.name}")
        archive.extractall(destination, members=members, filter="data")


def prepare_dataset(split: str, data_root: Path = ROOT / "data") -> dict:
    if split not in DATA_MD5:
        raise ValueError("本轮仅允许下载 dev-clean/test-clean；训练数据需另行确认")
    archive = data_root / "downloads" / f"{split}.tar.gz"
    url = f"https://www.openslr.org/resources/12/{split}.tar.gz"
    row = download(url, archive, DATA_MD5[split], "md5")
    marker = data_root / "LibriSpeech" / split / "asset_manifest.json"
    if not marker.is_file():
        safe_extract(archive, data_root)
    row.update({"split": split, "official_md5": DATA_MD5[split], "license": "CC-BY-4.0", "directory": str(marker.parent)})
    write_json(marker, row)
    print(f"PREPARED {split}", flush=True)
    return row


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", choices=["all", "model", *DATA_MD5], default="all")
    args = parser.parse_args()
    tasks = ["model", *DATA_MD5] if args.only == "all" else [args.only]
    with ThreadPoolExecutor(max_workers=len(tasks)) as pool:
        futures = {name: pool.submit(prepare_model if name == "model" else prepare_dataset, *([] if name == "model" else [name])) for name in tasks}
        # 任一下载失败都使命令失败；不会将缺失资源写成准备成功。
        results = {name: future.result() for name, future in futures.items()}
    write_json(ROOT / "audit/2026-09-18/downloads.json", results)
    print(json.dumps({"prepared": list(results)}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
