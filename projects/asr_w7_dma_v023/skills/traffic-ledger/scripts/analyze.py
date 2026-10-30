"""账本、覆盖率、互斥资源占用及部分重叠候选；不合并不同时间域。"""
import argparse
import csv
import html
import json
from collections import defaultdict
from pathlib import Path


def union_length(spans):
    total, end = 0, None
    for a, b in sorted(spans):
        if end is None or a > end:
            total += b - a
            end = b
        elif b > end:
            total += b - end
            end = b
    return total


def analyze(events):
    if not events or events[0].get('type') != 'metadata':
        raise ValueError('第一条必须metadata')
    meta = events[0]
    if meta.get('schema') != 1:
        raise ValueError('不支持schema')
    resources = meta['resources']
    txs, intervals, ids = [], defaultdict(list), set()
    for e in events[1:]:
        if e.get('type') not in ('transfer', 'interval'):
            raise ValueError('未知事件type')
        cfg = resources[e['resource']]
        if not cfg['start'] <= e['start'] < e['end'] <= cfg['end']:
            raise ValueError('事件时间越界或长度非正')
        if e['type'] == 'transfer':
            required = ('id', 'tensor', 'version', 'format', 'src', 'dst',
                        'op', 'phase', 'reason', 'valid_bytes', 'bus_bytes')
            if any(k not in e for k in required) or e['id'] in ids:
                raise ValueError('transfer缺字段或ID重复')
            if not 0 <= e['valid_bytes'] <= e['bus_bytes']:
                raise ValueError('valid/bus字节不合法')
            if e.get('logical_bytes', 0) < 0 or e.get('logical_offset', 0) < 0:
                raise ValueError('逻辑范围不合法')
            ids.add(e['id'])
            record = dict(e)
            # 辅助时间戳显式提供才计算；不从传输跨度猜设备首拍延迟。
            ordered = [e[k] for k in ('request', 'first_data', 'last_data', 'completion') if k in e]
            if ordered != sorted(ordered) or any(t < cfg['start'] or t > cfg['end'] for t in ordered):
                raise ValueError('辅助时间戳乱序或超出资源窗口')
            for out_key, a, b in [('first_data_latency_ticks','request','first_data'),
                                  ('data_span_ticks','first_data','last_data'),
                                  ('completion_tail_ticks','last_data','completion'),
                                  ('request_completion_ticks','request','completion')]:
                if a in e and b in e:
                    record[out_key] = e[b] - e[a]
            txs.append(record)
        else:
            if not e.get('state'):
                raise ValueError('interval缺state')
            valid, wire = e.get('bytes', 0), e.get('wire_bytes', e.get('bytes', 0))
            if not 0 <= valid <= wire:
                raise ValueError('interval字节不合法')
            if e['state'] != 'payload' and wire:
                raise ValueError('非payload状态不能计数据字节')
            cap = cfg.get('capacity_bytes_per_tick')
            if cap is not None and wire > cap * (e['end'] - e['start']):
                raise ValueError('资源传输超过配置容量')
            intervals[e['resource']].append(e)
    summaries, timeline = [], []
    for name, cfg in resources.items():
        if cfg['unit'] not in ('cycle', 'ns') or cfg['end'] <= cfg['start']:
            raise ValueError('资源时间基准不合法')
        cur, states, valid, wire, observed = cfg['start'], defaultdict(int), 0, 0, 0
        for e in sorted(intervals[name], key=lambda e: e['start']):
            if e['start'] < cur:
                raise ValueError('同资源状态重叠: ' + name)
            if e['start'] > cur:
                gap = dict(resource=name, start=cur, end=e['start'], state='unknown', reason='missing_coverage')
                timeline.append(gap)
                states['unknown'] += e['start'] - cur
            duration = e['end'] - e['start']
            states[e['state']] += duration
            observed += duration
            valid += e.get('bytes', 0)
            wire += e.get('wire_bytes', e.get('bytes', 0))
            timeline.append(e)
            cur = e['end']
        if cur < cfg['end']:
            states['unknown'] += cfg['end'] - cur
            timeline.append(dict(resource=name, start=cur, end=cfg['end'], state='unknown', reason='missing_coverage'))
        window = cfg['end'] - cfg['start']
        known = window - states.get('unknown', 0)
        hz = 1e9 if cfg['unit'] == 'ns' else cfg.get('clock_hz')
        if hz is not None and hz <= 0:
            raise ValueError('频率必须为正')
        seconds = window / hz if hz else None
        tx_valid = sum(e['valid_bytes'] for e in txs if e['resource'] == name)
        tx_wire = sum(e['bus_bytes'] for e in txs if e['resource'] == name)
        payload = states.get('payload', 0)
        summaries.append(dict(resource=name, unit=cfg['unit'], evidence=cfg.get('evidence', 'unspecified'),
                              window=window, observed_ticks=observed, known_ticks=known,
                              known_coverage=known/window, states=dict(states), valid_bytes=valid,
                              wire_bytes=wire, payload_fraction=payload/window,
                              bytes_per_tick=valid/window, seconds=seconds,
                              effective_B_per_s=valid/seconds if seconds else None,
                              payload_B_per_tick=valid/payload if payload else None,
                              capacity_bytes_per_tick=cfg.get('capacity_bytes_per_tick'),
                              ledger_valid_bytes=tx_valid, ledger_wire_bytes=tx_wire,
                              ledger_minus_interval_valid_bytes=tx_valid-valid,
                              ledger_minus_interval_wire_bytes=tx_wire-wire))
    groups = defaultdict(list)
    for e in txs:
        groups[tuple(e[k] for k in ('tensor', 'version', 'format', 'src', 'dst'))].append(e)
    tensors = []
    for key, group in groups.items():
        ranges, reasons = [], defaultdict(int)
        for e in group:
            reasons[e['reason']] += e['valid_bytes']
            if (e.get('status', 'success') == 'success' and 'logical_offset' in e
                    and 'logical_bytes' in e and e['logical_bytes'] == e['valid_bytes']):
                ranges.append((e['logical_offset'], e['logical_offset']+e['logical_bytes']))
        region_total = sum(b-a for a, b in ranges)
        unique = union_length(ranges)
        tensors.append(dict(zip(('tensor', 'version', 'format', 'src', 'dst'), key),
                            transfers=len(group), valid_bytes=sum(e['valid_bytes'] for e in group),
                            bus_bytes=sum(e['bus_bytes'] for e in group), comparable_logical_bytes=region_total,
                            unique_logical_bytes=unique, repeat_candidate_bytes=region_total-unique,
                            unclassified_transfers=len(group)-len(ranges), reasons=dict(reasons)))
    return dict(scope=meta.get('scope', 'unspecified'), resources=summaries, tensors=tensors,
                warnings=['重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。']), txs, timeline


def write_csv(path, rows):
    keys = list(dict.fromkeys(k for row in rows for k in row))
    with path.open('w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=keys)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else v for k, v in row.items()})


def render(out, summary, txs, intervals):
    out.mkdir(parents=True, exist_ok=True)
    (out/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    for name, rows in [('transfers', txs), ('resources', summary['resources']), ('intervals', intervals), ('tensors', summary['tensors'])]:
        write_csv(out/(name+'.csv'), rows)
    page = ['<!doctype html><meta charset="utf-8"><title>搬运时间轴</title><style>body{font:15px sans-serif;margin:28px;color:#172b4d}.lane{position:relative;height:48px;background:#edf1f5;margin:8px 0 22px}.block{position:absolute;height:44px;overflow:hidden;font-size:12px;border-right:1px solid white;box-sizing:border-box;padding:4px}h3{margin-bottom:4px}</style><h1>资源时间轴</h1><p>每行独立归一化；不同域未对齐，不可据此判断跨域并发。悬停查看事件。</p>']
    report = ['# 搬运与时间归因', '', summary['scope'], '', '|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|', '|---|---|---:|---:|---:|---:|']
    for r in summary['resources']:
        page.append('<h3>'+html.escape(r['resource'])+'</h3><div class="lane">')
        lane = [e for e in intervals if e['resource'] == r['resource']]
        origin = min(e['start'] for e in lane)
        for e in lane:
            color = '#78c5ad' if e['state']=='payload' else '#dce2e8' if e['state']=='unknown' else '#f4c77b'
            tip = html.escape(json.dumps(e, ensure_ascii=False), quote=True)
            page.append(f'<div class="block" style="left:{100*(e["start"]-origin)/r["window"]}%;width:{100*(e["end"]-e["start"])/r["window"]}%;background:{color}" title="{tip}">{html.escape(e["state"]+" "+str(e.get("transfer_id","")))}</div>')
        page.append('</div>')
        report.append(f'|{r["resource"]}|{r["unit"]}|{r["known_coverage"]:.1%}|{r["payload_fraction"]:.1%}|{r["valid_bytes"]}|{r["ledger_minus_interval_valid_bytes"]}|')
    report += ['', '## 重复搬运候选', '']
    for t in summary['tensors']:
        report.append(f'- {t["tensor"]} / {t["version"]} / {t["src"]}→{t["dst"]}：累计 {t["valid_bytes"]} B，已知区域并集 {t["unique_logical_bytes"]} B，重复候选 {t["repeat_candidate_bytes"]} B；原因 {t["reasons"]}。')
    report += ['', '等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。', '', *summary['warnings']]
    (out/'REPORT.md').write_text('\n'.join(report), encoding='utf-8')
    (out/'timeline.html').write_text('\n'.join(page), encoding='utf-8')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('trace', type=Path)
    p.add_argument('--out', type=Path, required=True)
    args = p.parse_args()
    events = [json.loads(s) for s in args.trace.read_text().splitlines() if s.strip()]
    result, txs, intervals = analyze(events)
    render(args.out, result, txs, intervals)
    print(json.dumps(dict(resources=len(result['resources']), transfers=len(txs), out=str(args.out)), ensure_ascii=False))


if __name__ == '__main__':
    main()
