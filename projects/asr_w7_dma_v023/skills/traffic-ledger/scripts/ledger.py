"""标准库 JSONL 记录器；不推断物理搬运或时钟。"""
import json
import time
from contextlib import contextmanager


class Ledger:
    def __init__(self, path, metadata):
        self.stream = open(path, 'w', encoding='utf-8')
        self.origin = time.perf_counter_ns()
        self.metadata = metadata
        self.emit(type='metadata', schema=1, **metadata)

    def emit(self, **event):
        self.stream.write(json.dumps(event, ensure_ascii=False) + '\n')
        self.stream.flush()

    def transfer(self, **fields):
        self.emit(type='transfer', **fields)

    def interval(self, **fields):
        self.emit(type='interval', **fields)

    @contextmanager
    def python_call(self, resource, operation, **fields):
        if self.metadata['resources'][resource]['unit'] != 'ns':
            raise ValueError('python_call只可使用单调时钟ns资源')
        start = time.perf_counter_ns() - self.origin
        try:
            yield
        finally:
            end = time.perf_counter_ns() - self.origin
            self.interval(resource=resource, start=start, end=end,
                          state='python_call', reason=operation,
                          evidence='python_wall_not_device_time', **fields)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.stream.close()
