# Third party sources

vendor/ contains the user's supplied ESPnet reading copy, retained byte for byte with its original copyright notices. The files identify the Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0

Model A checkpoint source: https://huggingface.co/pyf98/librispeech_conformer . The fixed revision and SHA256 come from the user's software4npu-main/scripts/download_models.py. Only the selected layer's original FP32 weights are included in this package. INT16 quantization happens on FPGA.
