"""Counter mapping for V022 only. Cycles are hardware observations, not estimates."""
FIELDS={1:'closed_plans',2:'conv_plans',3:'ffn_plans',4:'original_operators',6:'matrix_queues',7:'matrix_descriptors',12:'vector_layout_read_bytes',13:'vector_layout_write_bytes',15:'pl_instructions',57:'vector_elements',58:'layout_elements',59:'layout_cache_hits',60:'layout_cache_misses'}
PAIRS={8:'matrix_queue_cycles',10:'matrix_pe_cycles',16:'vector_cycles',18:'layout_cycles',20:'plan_fetch_cycles',22:'whole_plan_cycles',24:'ps_wait_ticks'}
def delta_plan(a,b):
    if b[30]!=2201:raise ValueError('Wrong plan counter ABI')
    r={name:(b[i]-a[i])&0xffffffff for i,name in FIELDS.items()}
    r.update({name:((b[i]|b[i+1]<<32)-(a[i]|a[i+1]<<32))&0xffffffffffffffff for i,name in PAIRS.items()})
    r.update({name.replace('_cycles','_seconds'):r[name]/125000000 for name in PAIRS.values() if name.endswith('_cycles')})
    r['ps_wait_seconds']=r['ps_wait_ticks']/33333000
    r['numeric_flags']=b[61];r['last_error']=b[27]
    r['scope']='Closed68 CONV/FFN only. Vector/layout DMA bytes exclude matrix DMA. Queue includes matrix transfer/wait, PE excludes it. Whole plan includes fetch/control: do not add inclusive wall times.'
    return r
