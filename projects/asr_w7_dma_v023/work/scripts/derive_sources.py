"""Copy/rename frozen source dependencies into an independent new project."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1';LEG=ROOT.parent/'model_a_lowbit_v13'
hashes={}
for source in [BASE/'rtl/axi_dma_v019.sv',LEG/'rtl/asr_fp32_alu.sv']:
    target=ROOT/'rtl'/source.name
    if target.exists():raise RuntimeError('Refuse overwrite')
    hashes[str(source)]=hashlib.sha256(source.read_bytes()).hexdigest()
    target.write_bytes(source.read_bytes())
(ROOT/'reports/SOURCE_BASELINE.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
print('V022_NUMERICAL_AND_DMA_SOURCES_COPIED_UNCHANGED')
