'use strict';

// The recording worklet loads this same file in its own audio thread.
if (typeof AudioWorkletProcessor !== 'undefined') {
  class MonoRecorder extends AudioWorkletProcessor {
    constructor() {
      super();
      this.block = new Float32Array(2048);
      this.used = 0;
      this.stopped = false;
      this.port.onmessage = () => {
        this.stopped = true;
        this.flush();
        this.port.postMessage('stopped');
      };
    }
    flush() {
      if (!this.used) return;
      const samples = this.block.slice(0, this.used);
      this.port.postMessage(samples, [samples.buffer]);
      this.used = 0;
    }
    process(inputs) {
      if (this.stopped) return false;
      const samples = inputs[0][0];
      if (!samples) return true;
      let offset = 0;
      while (offset < samples.length) {
        const size = Math.min(samples.length - offset, this.block.length - this.used);
        this.block.set(samples.subarray(offset, offset + size), this.used);
        this.used += size;
        offset += size;
        if (this.used === this.block.length) this.flush();
      }
      return true;
    }
  }
  registerProcessor('asr-mono-recorder', MonoRecorder);
} else {
  startConsole(document.currentScript.src);
}

function startConsole(workletUrl) {
  const SAMPLE_RATE = 16000;
  const MAX_SECONDS = 30;
  const SEGMENT_SECONDS = 10;
  const RECORD_SECONDS = 20;
  const MIN_SAMPLES = 1536;
  const el = id => document.getElementById(id);
  let services = {};
  let selection = null;
  let capture = null;
  let converting = false;
  let running = false;
  let checking = false;
  let statusVersion = 0;
  let statusTimer = null;
  let requestingWarmup = false;
  let warmupError = '';
  let copyingTimer = null;
  let segmentSession = null;

  function notice(message, error = false) {
    el('notice').textContent = message;
    el('notice').classList.toggle('error', error);
  }
  function updateControls() {
    const status = services.hybrid || {};
    const ready = status.ready === true && status.phase === 'ready';
    el('record').disabled = converting || (!capture && (running || !ready || services.busy === true));
    el('choose').disabled = running || converting || !!capture;
    el('submit').disabled = !selection || selection.autoSubmitted || running || converting || !!capture || !ready || services.busy === true;
    el('submit').firstChild.textContent = (running ? '识别中…' : selection?.autoSubmitted ? '录音已自动分段提交' : '识别所选文件') + ' ';
    el('warmup-panel').hidden = false;
    const busy = !running && services.busy ? '另一段语音正在处理。' : '';
    el('record').classList.toggle('recording', !!capture);
    el('record-label').textContent = capture ? '停止录音 · 提交尾段' : '开始分段录音';
    const labels = {
      cold: ['模型和实板待初始化', '初始化实板'],
      starting: ['正在初始化模型和实板', '初始化中…'],
      ready: ready ? ['模型和实板已就绪', '已就绪'] : ['正在核对就绪状态', '检查中…'],
      busy: ['实板正在识别', '使用中'],
      failed: ['实板初始化失败', '重新初始化']
    };
    const [title, button] = labels[status.phase] || [status.label || '检查实板状态…', '初始化实板'];
    el('warmup-title').textContent = running ? '实板正在识别' : title;
    el('warmup-detail').textContent = ((status.phase === 'failed' || status.phase === 'cold') && warmupError) ||
      `${busy}${status.detail || '初始化一次后，可连续发送多段录音。'}`;
    el('warmup').textContent = requestingWarmup ? '正在请求…' : button;
    el('warmup').disabled = requestingWarmup || running || services.busy === true || !['cold','failed'].includes(status.phase);
  }
  async function checkStatus(force = false) {
    if (checking && !force) return;
    clearTimeout(statusTimer);
    const version = ++statusVersion;
    checking = true;
    try {
      const response = await fetch('/api/status', {cache: 'no-store'});
      if (!response.ok) throw Error();
      const data = await response.json();
      if (version === statusVersion) services = data;
    } catch {
      const offline = {ready:false, label:'控制服务离线', detail:'重新启动本机控制服务后，页面会自动检查连接。'};
      if (version === statusVersion) services = {hybrid:offline};
    } finally {
      if (version === statusVersion) {
        checking = false;
        updateControls();
        const hybrid = services.hybrid || {};
        const fast = ['starting','busy'].includes(hybrid.phase) || (hybrid.phase === 'ready' && hybrid.ready !== true);
        if (!document.hidden && !running) statusTimer = setTimeout(checkStatus, fast ? 1000 : 10000);
      }
    }
  }
  el('warmup').onclick = async () => {
    if (el('warmup').disabled) return;
    requestingWarmup = true; warmupError = ''; updateControls();
    try {
      const response = await fetch('/api/warmup', {method:'POST'});
      const data = await response.json();
      if (!response.ok) throw Error(data.message || data.error || `初始化请求失败（HTTP ${response.status}）`);
      // Only GET /api/status confirms that the session is actually ready to use.
      if (data.phase === 'starting') services.hybrid = {...services.hybrid, phase:'starting', ready:false, detail:data.detail || '正在启动常驻会话…'};
    } catch (error) { warmupError = error.message || '无法连接初始化服务。'; }
    finally {
      await checkStatus(true);
      requestingWarmup = false; updateControls();
    }
  };
  updateControls();
  checkStatus();
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) clearTimeout(statusTimer);
    else if (!running) checkStatus();
  });

  function encodeWav(samples) {
    const wav = new ArrayBuffer(44 + samples.length * 2);
    const view = new DataView(wav);
    const tag = (offset, word) => { for (let i = 0; i < word.length; i++) view.setUint8(offset + i, word.charCodeAt(i)); };
    tag(0, 'RIFF'); view.setUint32(4, wav.byteLength - 8, true); tag(8, 'WAVE');
    tag(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
    view.setUint16(22, 1, true); view.setUint32(24, SAMPLE_RATE, true);
    view.setUint32(28, SAMPLE_RATE * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
    tag(36, 'data'); view.setUint32(40, samples.length * 2, true);
    for (let i = 0; i < samples.length; i++) {
      const sample = Math.max(-1, Math.min(1, samples[i]));
      view.setInt16(44 + i * 2, Math.min(32767, Math.round(sample * 32768)), true);
    }
    return new Blob([wav], {type:'audio/wav'});
  }
  function selectAudio(blob, frames, name) {
    if (frames < MIN_SAMPLES) throw Error('音频过短。至少需要 96 毫秒，请重新录音或选择更长的 WAV。');
    if (frames > SAMPLE_RATE * MAX_SECONDS) throw Error('音频超过 30 秒，请先截取要识别的部分。');
    if (selection) URL.revokeObjectURL(selection.url);
    const url = URL.createObjectURL(blob);
    selection = {name, blob, url, seconds:frames / SAMPLE_RATE};
    el('audio-title').textContent = name;
    el('audio-meta').textContent = `${selection.seconds.toFixed(2)} 秒 · 16 kHz · 单声道 PCM16`;
    el('player').src = url;
    el('player').hidden = false;
    notice('');
    updateControls();
  }
  // Return the sample count for input already in the board's native format.
  function nativePcmFrames(bytes) {
    const view = new DataView(bytes);
    const end = view.getUint32(4, true) + 8;
    if (end > bytes.byteLength) throw Error('WAV 文件不完整。');
    let native = false;
    for (let offset = 12; offset + 8 <= end;) {
      const type = view.getUint32(offset);
      const size = view.getUint32(offset + 4, true);
      const start = offset + 8;
      if (start + size > end) throw Error('WAV 数据块不完整。');
      if (type === 0x666d7420 && size >= 16) { // fmt
        native = view.getUint16(start, true) === 1 && view.getUint16(start + 2, true) === 1 &&
          view.getUint32(start + 4, true) === SAMPLE_RATE && view.getUint16(start + 12, true) === 2 &&
          view.getUint16(start + 14, true) === 16;
      }
      if (type === 0x64617461 && native) { // data
        if (size % 2) throw Error('WAV 音频数据长度有误。');
        return size / 2;
      }
      offset = start + size + (size % 2);
    }
    return null;
  }
  const offline = frames => new OfflineAudioContext(1, Math.max(1, frames), SAMPLE_RATE);
  async function loadUpload(file) {
    if (!file) return;
    segmentSession = null;
    if (selection) URL.revokeObjectURL(selection.url);
    selection = null;
    el('player').pause();
    el('player').removeAttribute('src');
    el('player').load();
    el('player').hidden = true;
    el('audio-title').textContent = '录一段语音，或选择文件';
    el('audio-meta').textContent = '英文 WAV · 96 毫秒至 30 秒';
    resetResults();
    converting = true;
    updateControls();
    try {
      if (file.size > 64 * 1024 * 1024) throw Error('文件超过 64 MB。请截取 30 秒以内的 WAV 音频。');
      const bytes = await file.arrayBuffer();
      const ascii = new TextDecoder('ascii');
      if (ascii.decode(bytes.slice(0,4)) !== 'RIFF' || ascii.decode(bytes.slice(8,12)) !== 'WAVE') throw Error('请选择 WAV 格式的音频。');
      const frames = nativePcmFrames(bytes);
      if (frames !== null) { selectAudio(file, frames, file.name); return; }
      const decoded = await offline(1).decodeAudioData(bytes);
      if (decoded.duration > MAX_SECONDS + 1 / SAMPLE_RATE) throw Error('音频超过 30 秒，请先截取要识别的部分。');
      const mono = new Float32Array(Math.min(decoded.length, MAX_SECONDS * SAMPLE_RATE));
      for (let c = 0; c < decoded.numberOfChannels; c++) {
        const channel = decoded.getChannelData(c);
        for (let i = 0; i < mono.length; i++) mono[i] += channel[i] / decoded.numberOfChannels;
      }
      selectAudio(encodeWav(mono), mono.length, file.name);
    } catch (e) { notice(e instanceof DOMException ? '浏览器无法解码这个 WAV 文件。' : e.message, true); }
    finally { converting = false; updateControls(); }
  }
  el('choose').onclick = () => { el('file').value = ''; el('file').click(); };
  el('file').onchange = () => loadUpload(el('file').files[0]);

  async function resampleBlocks(chunks, frames, sampleRate) {
    const samples = new Float32Array(frames);
    let offset = 0;
    for (const block of chunks) { samples.set(block, offset); offset += block.length; }
    if (sampleRate === SAMPLE_RATE) return samples;
    const converter = offline(Math.round(frames * SAMPLE_RATE / sampleRate));
    const buffer = converter.createBuffer(1, frames, sampleRate);
    buffer.copyToChannel(samples, 0);
    const source = converter.createBufferSource();
    source.buffer = buffer; source.connect(converter.destination); source.start();
    return (await converter.startRendering()).getChannelData(0);
  }
  function renderSegments(session) {
    if (segmentSession !== session) return;
    el('segment-panel').hidden = false;
    const names = {queued:'等待识别', processing:'识别中', done:'已完成', failed:'失败', cancelled:'未提交'};
    const rows = document.createDocumentFragment();
    for (const job of session.jobs) {
      const row = document.createElement('li');
      row.textContent = `第 ${job.number} 段 · ${job.start.toFixed(1)}–${job.end.toFixed(1)} 秒 · ${job.waiting ? '等待开发板空闲' : names[job.state]}` +
        (Number.isFinite(job.serviceSeconds) ? ` · 计算 ${job.serviceSeconds.toFixed(2)} 秒` : '') +
        (job.padded ? ' · 短尾已补静音' : '');
      rows.append(row);
    }
    el('segment-list').replaceChildren(rows);
    const queued = session.jobs.filter(job => job.state === 'queued').length;
    const done = session.jobs.filter(job => job.state === 'done').length;
    el('segment-status').textContent = session.failed ? '识别中断，已完成文字保留。' :
      capture?.session === session ? `正在录音 · 已完成 ${done} 段${queued ? ` · 排队 ${queued} 段` : ''}` :
      session.processing || queued ? `录音已停止 · 已完成 ${done} 段 · 等待剩余结果` : `全部 ${done} 段已完成`;
    const first = session.jobs.find(job => Number.isFinite(job.resultAt));
    const last = [...session.jobs].reverse().find(job => Number.isFinite(job.resultAt));
    const latency = [];
    if (first) latency.push(`首段文字：开始录音后 ${((first.resultAt - session.startedAt) / 1000).toFixed(2)} 秒`);
    if (session.stoppedAt && last && !session.processing && !queued && !session.failed)
      latency.push(`停止录音后等待 ${Math.max(0, (last.resultAt - session.stoppedAt) / 1000).toFixed(2)} 秒`);
    el('segment-latency').textContent = latency.join(' · ');
    if (session.jobs.length > 1) el('timing-basis').textContent = '各段计算用时累计，不含录音等待';
  }
  function queueSegment(state) {
    if (!state.segmentFrames || state.session.failed) return;
    const start = state.queuedFrames / state.context.sampleRate;
    const job = {number:state.session.jobs.length + 1, start,
      end:start + state.segmentFrames / state.context.sampleRate, state:'queued',
      chunks:state.segmentChunks, frames:state.segmentFrames, rate:state.context.sampleRate};
    state.queuedFrames += state.segmentFrames;
    state.segmentChunks = []; state.segmentFrames = 0;
    state.session.jobs.push(job);
    renderSegments(state.session);
    void drainSegments(state.session);
  }
  async function drainSegments(session) {
    if (session.processing || session.failed) return;
    session.processing = true; running = true; updateControls();
    try {
      for (const job of session.jobs) {
        if (job.state !== 'queued') continue;
        job.state = 'processing'; renderSegments(session);
        showStage(`第 ${job.number} 段 · 电脑准备输入特征`, 0);
        let samples = await resampleBlocks(job.chunks, job.frames, job.rate);
        job.chunks = null;
        if (samples.length < MIN_SAMPLES) {
          const padded = new Float32Array(MIN_SAMPLES); padded.set(samples); samples = padded; job.padded = true;
        }
        const received = await requestRecognition(encodeWav(samples), `录音-第${job.number}段.wav`, event => {
          if (event.type === 'queue_wait') { job.waiting = true; renderSegments(session); showStage(`第 ${job.number} 段 · 等待开发板空闲`, 0); }
          if (event.type === 'start') { job.waiting = false; renderSegments(session); }
          if (event.type === 'progress' && segmentSession === session) showFirmwareStage(event.stage, `第 ${job.number} 段 · `);
          if (event.type === 'result') {
            job.resultAt = performance.now();
            job.result = event;
            displaySegmentResults(session);
            renderSegments(session);
          }
        });
        job.result = received.result; job.serviceSeconds = received.seconds; job.state = 'done';
        showStage(`第 ${job.number} 段 · 编码与解码完成`, 12);
        renderSegments(session); displaySegmentResults(session);
      }
    } catch (error) {
      session.failed = true;
      const failed = session.jobs.find(job => job.state === 'processing');
      if (failed) { failed.state = 'failed'; failed.waiting = false; delete failed.result; delete failed.resultAt; }
      for (const job of session.jobs) if (job.state === 'queued') { job.state = 'cancelled'; job.chunks = null; }
      displaySegmentResults(session);
      el('stage-panel').hidden = true;
      notice(error.message || '分段识别失败。已完成文字保留，请检查连接。', true);
      el('runtime').textContent = '部分完成';
      if (capture?.session === session) void stopCapture();
    } finally {
      session.processing = false; running = false;
      renderSegments(session); updateControls(); void checkStatus();
    }
  }
  function displaySegmentResults(session) {
    if (segmentSession !== session) return;
    const completed = session.jobs.filter(job => job.result);
    displayText(completed.map(job => job.result.text?.trim()).filter(Boolean).join(' '));
    displayPieces(completed.flatMap(job => job.result.tokens || []), completed.flatMap(job => job.result.token_ids || []));
    el('token-origin').textContent = '各段 CTC 结果按顺序追加';
    el('result-mode').textContent = 'AXU15EGB · 10 秒分段';
    if (completed.length) {
      const total = { ...completed.at(-1).result };
      for (const key of ['pl_calls','encoder_frames','input_bytes','output_bytes','frontend_seconds','board_seconds','board_roundtrip_seconds','ctc_and_readout_seconds'])
        total[key] = completed.reduce((sum, job) => sum + (job.result[key] || 0), 0);
      displayHardware(total);
      const timed = completed.filter(job => Number.isFinite(job.serviceSeconds));
      if (timed.length === completed.length) {
        const seconds = timed.reduce((sum, job) => sum + job.serviceSeconds, 0);
        showTimings(total, seconds);
        el('timing-basis').textContent = '各段计算用时累计，不含录音等待';
        el('runtime').textContent = `累计计算 ${seconds.toFixed(2)} s`;
      }
    } else {
      el('hardware').hidden = true; el('timings').hidden = true;
    }
    el('result-status').textContent = `已收到 ${completed.length} 段结果。${el('transcript').textContent}`;
  }
  async function startCapture() {
    let stream, context;
    converting = true; notice(''); updateControls();
    try {
      if (!navigator.mediaDevices?.getUserMedia) throw Error('录音需要通过本机 localhost 或 HTTPS 打开此页面。');
      stream = await navigator.mediaDevices.getUserMedia({audio:{channelCount:1}});
      context = new AudioContext({sampleRate:SAMPLE_RATE});
      await context.audioWorklet.addModule(workletUrl);
      await context.resume();
      const source = context.createMediaStreamSource(stream);
      const node = new AudioWorkletNode(context, 'asr-mono-recorder', {channelCount:1, channelCountMode:'explicit'});
      const silent = context.createGain();
      silent.gain.value = 0;
      const session = {jobs:[], processing:false, failed:false, startedAt:performance.now(), stoppedAt:null};
      const state = {stream, context, node, frames:0, chunks:[], complete:null, timer:null,
        session, segmentChunks:[], segmentFrames:0, queuedFrames:0};
      node.port.onmessage = ({data}) => {
        if (data === 'stopped') { state.complete?.(); return; }
        const keep = Math.min(data.length, Math.max(0, RECORD_SECONDS * context.sampleRate - state.frames));
        if (!keep) return;
        const block = data.subarray(0, keep);
        state.chunks.push(block); state.frames += keep;
        let offset = 0;
        while (offset < keep) {
          const size = Math.min(keep - offset, SEGMENT_SECONDS * context.sampleRate - state.segmentFrames);
          state.segmentChunks.push(block.subarray(offset, offset + size));
          state.segmentFrames += size; offset += size;
          if (state.segmentFrames === SEGMENT_SECONDS * context.sampleRate) queueSegment(state);
        }
        let sum = 0;
        for (const sample of block) sum += sample * sample;
        el('level').style.transform = `scaleX(${Math.min(1, Math.sqrt(sum / keep) * 5)})`;
        el('record-status').textContent = `录音中 ${(state.frames / context.sampleRate).toFixed(1)} s`;
        if (state.frames >= RECORD_SECONDS * context.sampleRate && capture === state && !converting) void stopCapture();
      };
      capture = state;
      segmentSession = session;
      if (selection) URL.revokeObjectURL(selection.url);
      selection = null;
      resetResults();
      renderSegments(session);
      source.connect(node).connect(silent).connect(context.destination);
      el('player').pause(); el('player').hidden = true;
      el('meter').hidden = false;
      el('audio-title').textContent = '正在录音 · 每 10 秒自动识别'; el('audio-meta').textContent = '最长 20 秒；停止时会自动提交剩余语音';
      state.timer = setTimeout(() => { if (capture === state && !converting) void stopCapture(); }, (RECORD_SECONDS + 2) * 1000);
    } catch (e) {
      if (stream) stream.getTracks().forEach(track => track.stop());
      if (context && context.state !== 'closed') await context.close().catch(() => {});
      capture = null;
      const hints = {NotAllowedError:'浏览器没有获得麦克风权限。请允许录音，或选择 WAV 文件。',NotFoundError:'未找到麦克风，可以选择 WAV 文件。'};
      notice(hints[e.name] || e.message, true);
    } finally { converting = false; updateControls(); }
  }
  async function stopCapture() {
    const state = capture;
    if (!state || converting) return;
    state.session.stoppedAt = performance.now();
    converting = true; updateControls(); clearTimeout(state.timer);
    try {
      await new Promise(resolve => {
        const fallback = setTimeout(resolve, 650);
        state.complete = () => { clearTimeout(fallback); resolve(); };
        state.node.port.postMessage('stop');
      });
      if (!state.frames) throw Error('没有采集到音频，请检查麦克风。');
      queueSegment(state);
      let samples = await resampleBlocks(state.chunks, state.frames, state.context.sampleRate);
      if (samples.length < MIN_SAMPLES) { const padded = new Float32Array(MIN_SAMPLES); padded.set(samples); samples = padded; }
      selectAudio(encodeWav(samples), samples.length, '麦克风录音.wav');
      selection.autoSubmitted = true;
      if (state.session.failed) notice('分段识别中断，已完成文字保留；录音可试听。', true);
    } catch (e) {
      el('audio-title').textContent = selection?.name || '录一段语音，或选择文件';
      el('audio-meta').textContent = selection ? `${selection.seconds.toFixed(2)} 秒 · 16 kHz · 单声道 PCM16` : '英文语音 · WAV · 96 毫秒至 30 秒';
      el('player').hidden = !selection;
      notice(e.message, true);
    } finally {
      state.stream.getTracks().forEach(track => track.stop());
      state.node.port.close();
      await state.context.close().catch(() => {});
      el('meter').hidden = true; el('record-status').textContent = '';
      capture = null; converting = false; updateControls();
      renderSegments(state.session);
    }
  }
  el('record').onclick = () => capture ? stopCapture() : startCapture();

  function resetResults(message = '等待开始识别') {
    clearTimeout(copyingTimer);
    el('transcript').replaceChildren(); el('tokens').replaceChildren();
    el('token-panel').hidden = true; el('transcript').hidden = true; el('empty').hidden = false;
    el('empty').querySelector('p').textContent = message;
    el('result-mode').textContent = ''; el('result-status').textContent = '';
    el('runtime').textContent = '待运行'; el('hardware').hidden = true;
    el('stage-panel').hidden = true; el('timings').hidden = true;
    el('segment-panel').hidden = true;
    el('timing-basis').textContent = '按本次服务用时计算';
    el('count').textContent = '0';
    el('copy').textContent = '复制文本'; el('copy').disabled = true;
  }
  function displayText(text) {
    el('transcript').textContent = text;
    const hasText = !!el('transcript').textContent;
    el('transcript').hidden = !hasText; el('empty').hidden = hasText;
    el('copy').disabled = !hasText;
  }
  function displayPieces(pieces, ids) {
    const chips = document.createDocumentFragment();
    pieces.forEach((piece, i) => {
      const chip = document.createElement('span'); chip.className = 'piece';
      chip.textContent = piece === ' ' ? '␠' : piece;
      if (Number.isInteger(ids?.[i])) chip.title = `Token ID ${ids[i]}`;
      chips.append(chip);
    });
    el('tokens').replaceChildren(chips);
    el('token-panel').hidden = pieces.length === 0;
    el('token-origin').textContent = 'CTC 整句解码结果';
    el('count').textContent = String(pieces.length);
  }
  function showStage(label, layers) {
    el('stage-panel').hidden = false;
    el('stage-label').textContent = label;
    el('stage-progress').value = layers;
    el('stage-progress').setAttribute('aria-valuetext', label);
  }
  function showFirmwareStage(stage, prefix = '') {
    if (!Number.isInteger(stage)) return false;
    const frontend = ['第一遍卷积下采样', '第二遍卷积下采样', '投影到编码器输入'];
    if (stage >= 1 && stage <= 3) {
      showStage(`${prefix}板内准备特征 · ${frontend[stage - 1]}`, 0);
      return true;
    }
    if (stage === 300) {
      showStage(`${prefix}12 层编码结束 · 正在输出编码特征`, 12);
      return true;
    }
    const layer = Math.floor((stage - 100) / 10);
    const step = (stage - 100) % 10;
    const operators = ['第一前馈网络', '自注意力', '卷积模块', '第二前馈网络', '层归一化'];
    if (layer < 0 || layer >= 12 || step >= operators.length) return false;
    showStage(`${prefix}编码器第 ${layer + 1} / 12 层 · ${operators[step]}`, layer + step / 5);
    return true;
  }
  function showTimings(data, total) {
    const front = data.frontend_seconds, board = data.board_seconds;
    const roundtrip = data.board_roundtrip_seconds, ctc = data.ctc_and_readout_seconds;
    if (![total, front, board, roundtrip, ctc].every(v => Number.isFinite(v) && v >= 0) ||
        !total || roundtrip < board) return;
    const remainder = total - roundtrip - front - ctc;
    // done.seconds is rounded to milliseconds by the HTTP service.
    if (remainder < -0.00051) return;
    const rows = [
      ['板内编码（PS＋PL）', board],
      ['电脑与开发板传输、调度', roundtrip - board],
      ['电脑音频预处理', front],
      ['电脑 CTC 与结果读取', ctc],
      ['服务收尾及计时差额', Math.max(0, remainder)]
    ];
    const list = el('timing-rows'), bar = el('timing-bar');
    list.replaceChildren(); bar.replaceChildren();
    rows.forEach(([name, seconds], i) => {
      const percent = seconds * 100 / total;
      const row = document.createElement('div');
      row.className = `timing-row timing-${i}`;
      const term = document.createElement('dt'), value = document.createElement('dd');
      term.textContent = name;
      const pct = !percent ? '0%' : percent < 0.01 ? '<0.01%' : `${percent.toFixed(percent < 1 ? 2 : 1)}%`;
      value.textContent = `${seconds.toFixed(3)} s · ${pct}`;
      row.append(term, value); list.append(row);
      const segment = document.createElement('span'); segment.className = `timing-${i}`;
      segment.style.width = `${percent}%`; bar.append(segment);
    });
    el('timings').hidden = false;
  }
  function displayHardware(event) {
    const facts = [];
    if (event.gpu_used === false) facts.push('GPU 未使用');
    if (event.pc_conformer_loaded === false) facts.push('板内 PS＋PL 编码');
    if (Number.isInteger(event.encoder_frames)) facts.push(`${event.encoder_frames} 帧`);
    if (Number.isInteger(event.pl_calls)) facts.push(`${event.pl_calls} 次 PL 调用`);
    if (Number.isInteger(event.input_bytes) && Number.isInteger(event.output_bytes))
      facts.push(`发送 ${(event.input_bytes / 1024).toFixed(1)} KiB／回传 ${(event.output_bytes / 1024).toFixed(1)} KiB`);
    if (event.board_id) facts.push(`镜像 ${event.board_id}`);
    el('hardware').textContent = facts.join(' · ');
    el('hardware').hidden = false;
  }
  async function requestRecognition(blob, name, onEvent) {
    let response;
    const queueDeadline = performance.now() + 300000;
    while (true) {
      response = await fetch('/api/recognize?mode=hybrid', {method:'POST', body:blob,
        headers:{'Content-Type':'audio/wav','X-Audio-Name':encodeURIComponent(name)}});
      if (response.status !== 409) break;
      await response.text();
      onEvent({type:'queue_wait', message:'开发板正在处理其他录音，本段等待空闲后发送。'});
      while (true) {
        if (performance.now() >= queueDeadline) throw Error('等待开发板空闲超过 5 分钟，请检查其他控制页。');
        await new Promise(resolve => setTimeout(resolve, 500));
        const probe = await fetch('/api/status', {cache:'no-store'});
        if (!probe.ok) throw Error('无法检查开发板状态。');
        const state = await probe.json();
        if (state.hybrid?.phase === 'failed') throw Error(state.hybrid.detail || '实板连接需要恢复。');
        if (state.busy === false && state.hybrid?.ready === true) break;
      }
    }
    if (!response.ok) {
      const body = await response.text();
      let message; try { const data = JSON.parse(body); message = data.message || data.error; } catch { /* Plain response. */ }
      throw Error(message || body.slice(0, 300) || `服务返回 HTTP ${response.status}`);
    }
    let result, seconds, finished = false;
    function onLine(line) {
      if (!line.trim()) return;
      if (finished) throw Error('控制服务在完成后返回了额外数据。');
      const event = JSON.parse(line);
      if (event.type === 'error') throw Error(event.message || '识别失败。');
      if (event.type === 'result') {
        if (result) throw Error('控制服务重复返回识别结果。');
        result = event;
      }
      if (event.type === 'done') {
        if (!result || !Number.isFinite(event.seconds) || event.seconds < 0) throw Error('识别完成记录不完整。');
        seconds = event.seconds; finished = true;
      }
      onEvent(event);
    }
    const reader = response.body.getReader(), decoder = new TextDecoder(); let pending = '';
    try {
      while (true) {
        const {done, value} = await reader.read();
        pending += done ? decoder.decode() : decoder.decode(value, {stream:true});
        const lines = pending.split('\n'); pending = lines.pop(); lines.forEach(onLine);
        if (done) break;
      }
      onLine(pending);
    } finally { reader.releaseLock(); }
    if (!finished) throw Error('连接中断，控制服务没有返回完成状态。');
    return {result, seconds};
  }
  async function recognize() {
    if (el('submit').disabled) return;
    running = true; updateControls(); resetResults('等待识别结果…'); notice('');
    el('result-mode').textContent = 'AXU15EGB';
    showStage('电脑准备输入特征', 0);
    el('runtime').textContent = '运行中';
    let finished = false;
    let measurement;
    function acceptResult(event) {
      displayText(event.text || '');
      displayPieces(event.tokens || [], event.token_ids);
      measurement = event;
      showStage('编码完成 · 电脑 CTC 贪心解码完成', 12);
      displayHardware(event);
    }
    function onEvent(event) {
      if (event.type === 'queue_wait') { notice(event.message); showStage('等待开发板空闲', 0); }
      if (event.type === 'progress') {
        if (!showFirmwareStage(event.stage)) notice(event.message || '识别中…');
      }
      if (event.type === 'result') acceptResult(event);
      if (event.type === 'done') {
        finished = true;
        el('runtime').textContent = Number.isFinite(event.seconds) ? `服务用时 ${event.seconds.toFixed(2)} s` : '已完成';
        if (measurement) showTimings(measurement, event.seconds);
        if (!el('transcript').textContent) el('empty').querySelector('p').textContent = '未识别到文字';
        el('result-status').textContent = `识别完成。${el('transcript').textContent}`;
      }
    }
    try {
      await requestRecognition(selection.blob, selection.name, onEvent);
      notice('');
    } catch (e) {
      el('runtime').textContent = '未完成'; el('empty').querySelector('p').textContent = '识别未完成';
      el('stage-panel').hidden = true; el('timings').hidden = true;
      notice(e.message || '无法连接控制服务。', true);
    } finally { running = false; updateControls(); checkStatus(); }
  }
  el('submit').onclick = recognize;
  el('copy').onclick = async () => {
    try {
      await navigator.clipboard.writeText(el('transcript').textContent); el('copy').textContent = '已复制';
      clearTimeout(copyingTimer); copyingTimer = setTimeout(() => { el('copy').textContent = '复制文本'; }, 1500);
    } catch { notice('浏览器未允许访问剪贴板，请选中识别文本后复制。', true); }
  };
}
