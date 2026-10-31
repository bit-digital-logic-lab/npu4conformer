"""将活动JSONL渲染为离线交互波形；不同timebase不对齐。"""
import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path


def normalize_interval(event, cfg):
    """Legacy busy samples must not become effective compute evidence."""
    e = dict(event)
    evidence = ' '.join(str(x) for x in (cfg.get('evidence', ''), e.get('evidence', ''), e.get('reason', ''))).lower()
    if e.get('state') in ('compute', 'active') and (cfg.get('state_semantics') == 'busy_flag' or 'busy' in evidence):
        e['original_state'] = e['state']
        e['state'] = 'busy'
        e['state_semantics'] = 'busy_flag_not_effective_compute'
    return e


def prepare(events):
    if not events or events[0].get('type') != 'metadata' or events[0].get('schema') != 1:
        raise ValueError('需要schema=1的metadata')
    meta = events[0]
    resources = meta['resources']
    groups, lanes, intervals = {}, [], defaultdict(list)
    for e in events[1:]:
        if e.get('type') == 'transfer':
            continue
        if e.get('type') != 'interval' or e.get('resource') not in resources:
            raise ValueError('未知事件或资源')
        cfg = resources[e['resource']]
        if not cfg['start'] <= e['start'] < e['end'] <= cfg['end'] or not str(e.get('state', '')):
            raise ValueError('时间越界/无状态')
        intervals[e['resource']].append(normalize_interval(e, cfg))
    for name, cfg in resources.items():
        if cfg.get('unit') not in ('cycle', 'ns') or cfg['end'] <= cfg['start']:
            raise ValueError('资源时间基准不合法')
        group = cfg.get('timebase', 'unaligned:' + name)
        signature = (cfg['unit'], cfg.get('clock_hz'), cfg.get('origin_ns'))
        if group in groups and groups[group]['signature'] != signature:
            raise ValueError('同timebase的单位/频率/epoch不一致')
        if group not in groups:
            groups[group] = dict(signature=signature, name=group, unit=cfg['unit'], clock_hz=cfg.get('clock_hz'), start=cfg['start'], end=cfg['end'])
        groups[group]['start'] = min(groups[group]['start'], cfg['start'])
        groups[group]['end'] = max(groups[group]['end'], cfg['end'])
        cur, spans, states = cfg['start'], [], defaultdict(float)
        for e in sorted(intervals[name], key=lambda x: x['start']):
            if e['start'] < cur:
                raise ValueError('同lane活动重叠: ' + name)
            if e['start'] > cur:
                spans.append(dict(start=cur, end=e['start'], state='unknown', reason='missing_coverage'))
            spans.append(dict(e))
            cur = e['end']
        if cur < cfg['end']:
            spans.append(dict(start=cur, end=cfg['end'], state='unknown', reason='missing_coverage'))
        for e in spans:
            e['state'] = str(e['state'])
            states[e['state']] += e['end'] - e['start']
        lanes.append(dict(name=name, group=group, kind=cfg.get('kind', 'module'), start=cfg['start'], end=cfg['end'],
                          evidence=cfg.get('evidence', 'unspecified'), states=dict(states), spans=spans,
                          known_coverage=1-states.get('unknown', 0)/(cfg['end']-cfg['start'])))
    for g in groups.values():
        del g['signature']
    return dict(scope=meta.get('scope', 'unspecified'), groups=list(groups.values()), lanes=lanes)


def render(trace, out, title):
    data = prepare([json.loads(s) for s in trace.read_text().splitlines() if s.strip()])
    data['title'] = title
    data['input_sha256'] = hashlib.sha256(trace.read_bytes()).hexdigest()
    out.parent.mkdir(parents=True, exist_ok=True)
    template = Path(__file__).with_name('viewer.html').read_text()
    # 防止输入中的标签/脚本字符串穿出JSON数据容器。
    encoded = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    out.write_text(template.replace('__TRACE_JSON__', encoded), encoding='utf-8')
    summary = dict(scope=data['scope'], input_sha256=data['input_sha256'], groups=data['groups'],
                   lanes=[{k:v for k,v in lane.items() if k!='spans'} for lane in data['lanes']])
    out.with_suffix('.summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    return data


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('trace', type=Path)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--title', default='模块活动波形')
    a=p.parse_args()
    data=render(a.trace,a.out,a.title)
    print(json.dumps(dict(out=str(a.out),lanes=len(data['lanes']),timebases=len(data['groups'])),ensure_ascii=False))
