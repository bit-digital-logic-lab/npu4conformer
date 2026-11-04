"""Read Windows memory headroom without changing system configuration."""
import ctypes
import datetime
import json

class MemoryStatus(ctypes.Structure):
    _fields_ = [('length', ctypes.c_uint32), ('load', ctypes.c_uint32)] + [
        (name, ctypes.c_uint64) for name in ('total_phys', 'avail_phys', 'total_pagefile',
        'avail_pagefile', 'total_virtual', 'avail_virtual', 'avail_extended')]

state = MemoryStatus()
state.length = ctypes.sizeof(state)
if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(state)):
    raise ctypes.WinError()
print(json.dumps({'time': datetime.datetime.now().astimezone().isoformat(),
                  'free_physical_gib': round(state.avail_phys / 2**30, 3),
                  'available_commit_gib': round(state.avail_pagefile / 2**30, 3),
                  'total_commit_gib': round(state.total_pagefile / 2**30, 3)}))
