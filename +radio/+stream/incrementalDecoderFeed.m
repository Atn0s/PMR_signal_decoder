function [state, result] = incrementalDecoderFeed(state, chunk)
%INCREMENTALDECODERFEED Append new IQ once and decode bounded recent history.
radio.stream.validateIqChunk(chunk);
if chunk.sampleRateHz ~= state.sampleRateHz
    error('radio:stream:incrementalDecoderFeed:SampleRate', ...
        'Chunk and incremental decoder sample rates differ.');
end
if isfield(state, 'nativeStreaming') && state.nativeStreaming
    [state, result] = feedNativeProtocol(state, chunk);
    return;
end
reset = logical(chunk.discontinuity);
if ~isempty(state.nextExpectedSample) && ...
        chunk.sourceSampleStart ~= state.nextExpectedSample
    reset = true;
end
if reset
    state.historyIq = complex(zeros(0, 1, 'single'));
    state.historyStartSample = chunk.sourceSampleStart;
    state.resetCount = state.resetCount + uint64(1);
end
if isempty(state.historyIq)
    state.historyStartSample = chunk.sourceSampleStart;
end
state.historyIq = [state.historyIq; single(chunk.iq(:))];
if numel(state.historyIq) > state.historyCapacitySamples
    drop = numel(state.historyIq) - state.historyCapacitySamples;
    state.historyIq = state.historyIq(drop+1:end);
    state.historyStartSample = state.historyStartSample + uint64(drop);
end
state.nextExpectedSample = chunk.sourceSampleEnd;
state.feedCount = state.feedCount + uint64(1);
state.inputSampleCount = state.inputSampleCount + uint64(numel(chunk.iq));

snapshot = radio.stream.makeIqChunk( ...
    state.historyIq, state.sampleRateHz, state.historyStartSample, ...
    'ChannelId', chunk.channelId, ...
    'SequenceNumber', chunk.sequenceNumber, ...
    'CenterFrequencyHz', chunk.centerFrequencyHz, ...
    'Discontinuity', reset, ...
    'DroppedSourceSamples', chunk.droppedSourceSamples);
token = tic;
if isempty(state.decodeFcn)
    [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        radio.stream.decodeProtocolWindow(state.protocol, snapshot);
else
    [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        state.decodeFcn(state.protocol, snapshot);
end
state.lastDiagnostics = diagnostics;
state.lastFrequencyOffsetHz = frequencyOffsetHz;
state.lastTimingState = timingState;
result = struct( ...
    'snapshot', snapshot, ...
    'pdus', pdus, ...
    'diagnostics', diagnostics, ...
    'frequencyOffsetHz', frequencyOffsetHz, ...
    'timingState', timingState, ...
    'historySampleCount', numel(state.historyIq), ...
    'newInputSampleCount', numel(chunk.iq), ...
    'reset', reset, ...
    'elapsedSec', toc(token));
end

function [state, result] = feedNativeProtocol(state, chunk)
reset = logical(chunk.discontinuity);
if ~isempty(state.nextExpectedSample) && ...
        chunk.sourceSampleStart ~= state.nextExpectedSample
    reset = true;
end
if reset
    state.nativeState = [];
    state.nativeSeed = [];
    state.nextExpectedSample = [];
    state.resetCount = state.resetCount + uint64(1);
end

if isempty(state.nativeState)
    if ~isempty(state.nativeSeed)
        seed = state.nativeSeed;
        seed.discontinuity = false;
        state.nativeState = nativeInit( ...
            state.protocol, state.sampleRateHz, seed.sourceSampleStart);
        [state.nativeState, ~] = nativeFeed( ...
            state.protocol, state.nativeState, seed);
        state.nativeSeed = [];
    else
        state.nativeState = nativeInit( ...
            state.protocol, state.sampleRateHz, chunk.sourceSampleStart);
    end
end

nativeChunk = chunk;
nativeChunk.discontinuity = false;
token = tic;
[state.nativeState, decoded] = nativeFeed( ...
    state.protocol, state.nativeState, nativeChunk);
state.nextExpectedSample = chunk.sourceSampleEnd;
state.feedCount = state.feedCount + uint64(1);
state.inputSampleCount = state.inputSampleCount + uint64(numel(chunk.iq));
state.lastDiagnostics = decoded.diagnostics;
state.lastFrequencyOffsetHz = decoded.frequencyOffsetHz;
state.lastTimingState = decoded.timingState;
retainedTargetSamples = nativeRetainedTargetSamples(state.nativeState);
retainedInputSamples = round(retainedTargetSamples * ...
    state.sampleRateHz / state.nativeState.targetSampleRateHz);

result = struct( ...
    'snapshot', chunk, ...
    'pdus', decoded.pdus, ...
    'sourceSamples', decoded.sourceSamples, ...
    'diagnostics', decoded.diagnostics, ...
    'frequencyOffsetHz', decoded.frequencyOffsetHz, ...
    'timingState', decoded.timingState, ...
    'historySampleCount', retainedInputSamples, ...
    'newInputSampleCount', numel(chunk.iq), ...
    'reset', reset, ...
    'nativeStreaming', true, ...
    'elapsedSec', toc(token));
end

function native = nativeInit(protocol, sampleRateHz, sourceSampleStart)
switch protocol
    case 'DMR'
        native = dmr.streamInit(sampleRateHz, dmr.config(), ...
            'SourceSampleStart', sourceSampleStart);
    case 'NXDN'
        native = nxdn.streamInit(sampleRateHz, nxdn.config(), ...
            'SourceSampleStart', sourceSampleStart);
    case 'P25'
        native = p25.streamInit(sampleRateHz, p25.config(), ...
            'SourceSampleStart', sourceSampleStart);
    case 'dPMR'
        native = dpmr.streamInit(sampleRateHz, dpmr.config(), ...
            'SourceSampleStart', sourceSampleStart);
    case 'TETRA'
        native = tetra.streamInit(sampleRateHz, tetra.config(), ...
            'SourceSampleStart', sourceSampleStart);
    otherwise
        error('radio:stream:incrementalDecoderFeed:NativeProtocol', ...
            'No native stream decoder is registered for %s.', protocol);
end
end

function [native, decoded] = nativeFeed(protocol, native, chunk)
switch protocol
    case 'DMR'
        [native, decoded] = dmr.streamDecodeChunk(native, chunk);
    case 'NXDN'
        [native, decoded] = nxdn.streamDecodeChunk(native, chunk);
    case 'P25'
        [native, decoded] = p25.streamDecodeChunk(native, chunk);
    case 'dPMR'
        [native, decoded] = dpmr.streamDecodeChunk(native, chunk);
    case 'TETRA'
        [native, decoded] = tetra.streamDecodeChunk(native, chunk);
    otherwise
        error('radio:stream:incrementalDecoderFeed:NativeProtocol', ...
            'No native stream decoder is registered for %s.', protocol);
end
end

function count = nativeRetainedTargetSamples(native)
count = 0;
if isfield(native, 'demodBuffer')
    count = numel(native.demodBuffer);
end
if isfield(native, 'calibrationBuffer')
    count = max(count, numel(native.calibrationBuffer));
end
if isfield(native, 'matchedBuffer')
    count = max(count, numel(native.matchedBuffer));
end
if isfield(native, 'bitBuffer') && isfield(native, 'cfg') && ...
        isfield(native.cfg, 'symbolRateHz')
    bitEquivalent = ceil(numel(native.bitBuffer) * ...
        native.targetSampleRateHz / (2 * native.cfg.symbolRateHz));
    count = max(count, bitEquivalent);
end
end
