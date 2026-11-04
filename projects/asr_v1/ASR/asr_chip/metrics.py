"""纯 Python 的词错误率，固定归一化规则与编辑计数。

默认仅小写和合并空白，不删除标点。可选删除所有 Unicode P 类标点，
例如 DON'T -> dont；此规则必须在浮点和量化实验中保持相同。
WER = (S + D + I) / N，允许大于 1。全部参考为空时按 jiwer 4 的约定，
返回插入词数；参考和假设都为空则为 0。
"""

from __future__ import annotations

from typing import Sequence
import unicodedata


def normalize_text(
    text: str, *, lowercase: bool = True, remove_punctuation: bool = False
) -> str:
    if not isinstance(text, str):
        raise TypeError("参考与识别文本必须是字符串")
    if lowercase:
        text = text.lower()
    if remove_punctuation:
        text = "".join(char for char in text if not unicodedata.category(char).startswith("P"))
    return " ".join(text.split())


def _edit_counts(reference: list[str], hypothesis: list[str]) -> dict[str, int]:
    # 每格只保存 S/D/I；相同最短距离时固定优先对角、删除、插入。
    # 仅保留两行，空间为 O(假设词数)，避免长音频分配完整对齐矩阵。
    previous = [(0, 0, count) for count in range(len(hypothesis) + 1)]
    for r_index, ref in enumerate(reference, 1):
        current = [(0, r_index, 0)]
        for h_index, hyp in enumerate(hypothesis, 1):
            substitutions, deletions, insertions = previous[h_index - 1]
            diagonal = (substitutions + (ref != hyp), deletions, insertions)
            substitutions, deletions, insertions = previous[h_index]
            deletion = (substitutions, deletions + 1, insertions)
            substitutions, deletions, insertions = current[-1]
            insertion = (substitutions, deletions, insertions + 1)
            current.append(min((diagonal, deletion, insertion), key=sum))
        previous = current
    substitutions, deletions, insertions = previous[-1]
    return {
        "substitutions": substitutions,
        "deletions": deletions,
        "insertions": insertions,
        "hits": len(reference) - substitutions - deletions,
        "reference_words": len(reference),
        "hypothesis_words": len(hypothesis),
        "errors": substitutions + deletions + insertions,
    }


def compute_wer(
    references: Sequence[str],
    hypotheses: Sequence[str],
    *,
    lowercase: bool = True,
    remove_punctuation: bool = False,
) -> dict:
    """逐句对齐后汇总 S/D/I/N，返回 WER 比例和每句计数。

    不跨语句做对齐；不对每句 WER 取平均。最短对齐并列时 S/D/I 分配
    可能与其他库不同，但总编辑距离和 WER 一致。空数据集被拒绝。
    """
    if isinstance(references, (str, bytes)) or isinstance(hypotheses, (str, bytes)):
        raise TypeError("请传入字符串列表；单句也应使用 [text]")
    references, hypotheses = list(references), list(hypotheses)
    if len(references) != len(hypotheses):
        raise ValueError("参考文本与识别文本的条数不一致")
    if not references:
        raise ValueError("不能对空数据集计算 WER")
    totals = {key: 0 for key in (
        "substitutions", "deletions", "insertions", "hits", "reference_words",
        "hypothesis_words", "errors",
    )}
    utterances = []
    for index, (ref, hyp) in enumerate(zip(references, hypotheses)):
        normalized_ref = normalize_text(ref, lowercase=lowercase, remove_punctuation=remove_punctuation)
        normalized_hyp = normalize_text(hyp, lowercase=lowercase, remove_punctuation=remove_punctuation)
        counts = _edit_counts(normalized_ref.split(), normalized_hyp.split())
        for key, value in counts.items():
            totals[key] += value
        row_wer = counts["errors"] / counts["reference_words"] if counts["reference_words"] else float(counts["insertions"])
        utterances.append({
            "index": index, "reference": normalized_ref, "hypothesis": normalized_hyp,
            **counts, "wer": row_wer,
        })
    score = totals["errors"] / totals["reference_words"] if totals["reference_words"] else float(totals["insertions"])
    return {
        **totals,
        "utterance_count": len(utterances),
        "wer": score,
        "wer_percent": 100.0 * score,
        "normalization": {
            "lowercase": lowercase,
            "remove_punctuation": remove_punctuation,
            "punctuation_definition": "Unicode category P; characters deleted without replacement",
            "whitespace": "split and join with one space",
        },
        "empty_reference_policy": "N=0: insertion count; empty/empty: 0",
        "per_utterance": utterances,
    }
