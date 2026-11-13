"""Restore the published v1 attachment. Standard library only; no board access."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
URL = "https://github.com/bit-digital-logic-lab/npu4conformer/releases/download/v1/asr_v1_assets.zip"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def metadata(root):
    return json.loads((root / "release_assets.json").read_text(encoding="utf-8-sig"))


def destination(root, name):
    relative = PurePosixPath(name)
    if relative.is_absolute() or ".." in relative.parts or "\\" in name or ":" in name:
        raise ValueError(f"Invalid asset path: {name}")
    target = root.joinpath(*relative.parts)
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Asset escapes project: {name}")
    return target


def audit(root, manifest=None):
    manifest = manifest or metadata(root)
    missing, mismatched = [], []
    for name, spec in manifest["files"].items():
        path = destination(root, name)
        if not path.is_file():
            missing.append(name)
        elif path.stat().st_size != spec["bytes"] or sha(path) != spec["sha256"]:
            mismatched.append(name)
    return dict(passed=not missing and not mismatched, checked=len(manifest["files"]),
                missing=missing, mismatched=mismatched, hardware_access=False)


def restore(archive, root=ROOT):
    root = root.resolve()
    manifest = metadata(root)
    if archive.stat().st_size != manifest["bytes"] or sha(archive) != manifest["sha256"]:
        raise ValueError("ZIP 大小或 SHA-256 与 v1 发布清单不符，未解压。")
    expected = manifest["files"]
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        if len(names) != len(set(names)):
            raise ValueError("ZIP contains duplicate paths")
        # Validate every selected entry and every existing destination first.
        pending = []
        for name, spec in expected.items():
            path = destination(root, name)
            info = bundle.getinfo("asr_v1/" + name)
            if info.file_size != spec["bytes"] or (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f"Invalid archive member: {name}")
            if path.exists():
                if not path.is_file() or path.stat().st_size != spec["bytes"] or sha(path) != spec["sha256"]:
                    raise ValueError(f"已有不同版本文件，已保留且停止恢复：{name}")
            else:
                pending.append((name, spec, path))
        # Stage all missing members, so a damaged ZIP never publishes partial bytes.
        with tempfile.TemporaryDirectory(prefix=".asset-restore-", dir=root) as scratch:
            for index, (name, spec, path) in enumerate(pending):
                staged = Path(scratch) / str(index)
                with bundle.open("asr_v1/" + name) as src, staged.open("xb") as dst:
                    shutil.copyfileobj(src, dst)
                if sha(staged) != spec["sha256"]:
                    raise ValueError(f"Asset SHA-256 mismatch: {name}")
            for index, (name, spec, path) in enumerate(pending):
                path.parent.mkdir(parents=True, exist_ok=True)
                with (Path(scratch) / str(index)).open("rb") as src, path.open("xb") as dst:
                    shutil.copyfileobj(src, dst)
    result = audit(root, manifest)
    result["restored"] = len(pending)
    return result


def gui():
    import tkinter as tk
    from tkinter import filedialog, messagebox
    import queue
    import threading
    import webbrowser
    window = tk.Tk()
    window.title("ASR v1 文件恢复")
    window.geometry("650x300")
    tk.Label(window, text="源码与 Release 附件需要合并", font=("Microsoft YaHei", 15)).pack(pady=15)
    tk.Label(window, text="1. 下载 asr_v1_assets.zip\n2. 选择 ZIP 并恢复到本项目\n恢复时核对哈希；不连接开发板，不生成验收凭据。", justify="left").pack()
    label = tk.StringVar(value=str(ROOT))
    messages = queue.Queue()
    buttons = []

    def start(action):
        for button in buttons:
            button.configure(state="disabled")
        label.set("正在校验文件，请稍候…")
        def work():
            try:
                messages.put((True, action()))
            except Exception as exc:
                messages.put((False, str(exc)))
        threading.Thread(target=work).start()

    def choose():
        selected = filedialog.askopenfilename(title="选择 asr_v1_assets.zip", filetypes=[("ZIP", "*.zip")])
        if selected:
            start(lambda: restore(Path(selected)))

    def poll():
        try:
            ok, value = messages.get_nowait()
        except queue.Empty:
            window.after(100, poll)
            return
        for button in buttons:
            button.configure(state="normal")
        if ok:
            label.set(f"检查 {value['checked']} 个文件；缺失 {len(value['missing'])}，不匹配 {len(value['mismatched'])}。")
            if value["passed"]:
                messagebox.showinfo("文件完整", "68 个附件文件齐全。下一步见 DEPLOYMENT_V1.md；尚未上板验收。")
            else:
                messagebox.showwarning("文件未齐", "\n".join((value['missing'] + value['mismatched'])[:8]))
        else:
            label.set("恢复未完成；已有不同版本文件不会被覆盖。")
            messagebox.showerror("恢复失败", value)
        window.after(100, poll)

    for text, command in (("打开附件下载", lambda: webbrowser.open(URL)), ("选择 ZIP 并恢复", choose),
                          ("检查本地附件", lambda: start(lambda: audit(ROOT)))):
        button = tk.Button(window, text=text, command=command)
        button.pack(pady=4)
        buttons.append(button)
    tk.Label(window, textvariable=label, wraplength=620).pack(pady=8)
    def close():
        if any(str(button['state']) == 'disabled' for button in buttons):
            messagebox.showinfo("正在处理", "请等本次文件校验或恢复完成后再关闭。")
        else:
            window.destroy()
    window.protocol("WM_DELETE_WINDOW", close)
    window.after(100, poll)
    window.mainloop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.zip or args.check:
        result = restore(args.zip) if args.zip else audit(ROOT)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        raise SystemExit(0 if result["passed"] else 1)
    gui()
