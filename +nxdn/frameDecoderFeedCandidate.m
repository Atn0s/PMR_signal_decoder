function [state, pdus] = frameDecoderFeedCandidate( ...
        state, samples, candidate, varargin)
%FRAMEDECODERFEEDCANDIDATE Decode one complete FSW-aligned NXDN96 frame.
p = inputParser;
p.addParameter('FsStartOffset', 0);
p.parse(varargin{:});
if state.finalized
    error('nxdn:frameDecoderFeedCandidate:Finalized', ...
        'Cannot feed a finalized NXDN frame decoder.');
end

cfg = state.cfg;
c = nxdn.constants();
state.candidateCount = state.candidateCount + uint64(1);
frameIndex = double(state.candidateCount);
pdus = struct([]);

[symbols, recovery] = nxdn.recoverFrameSymbols(samples, candidate, cfg);
if isempty(symbols), return; end
fsStart = recovery.fsStart + double(p.Results.FsStartOffset);
[dibits, ~, decisionError] = nxdn.sliceDibits(symbols);
lich = nxdn.decodeLich(dibits(11:18), cfg);
fr = state.frameTemplate;
fr.fs_start = fsStart;
fr.sync_score = recovery.fswScore;
fr.mean_decision_error = mean(decisionError);
fr.lich_ok = lich.ok;
fr.lich = lich.value;
if lich.ok
    state.lichOkCount = state.lichOkCount + uint64(1);
    if state.retainDiagnostics
        state.lichValues(end+1, 1) = lich.value;
    end
else
    state = appendFrame(state, fr);
    return;
end

frameInfo = nxdn.frameInfoFromLich(lich);
fr.rf_channel_type = frameInfo.rf_channel_type;
fr.functional_channel = frameInfo.functional_channel;
fr.direction = frameInfo.direction;
fr.voice_present = frameInfo.voice_present;
fr.supported = frameInfo.supported;
if ~frameInfo.supported
    state = appendFrame(state, fr);
    return;
end

scrambled = nxdn.descrambleDibits(dibits(11:192));
frameBits = nxdn.dibitsToBits(scrambled);
context = makeContext( ...
    frameInfo, lich.value, fsStart, frameIndex, state.lastRan);

if frameInfo.sacch
    block = nxdn.decodeSacch( ...
        frameBits(c.sacchBitStart:c.sacchBitEnd), frameInfo);
    fr.sacch_ok = block.ok;
    state = appendBlock(state, block, fsStart, 0);
    if block.ok
        state.lastRan = block.ran;
        context.ran = state.lastRan;
        [state.sacchState, assembled] = nxdn.sacchAssemblerFeed( ...
            state.sacchState, block, frameInfo, fsStart, cfg);
        if ~isempty(assembled)
            state.sacchAssemblyCount = ...
                state.sacchAssemblyCount + uint64(1);
            sacchContext = context;
            sacchContext.functional_channel = 'SACCH';
            sacchContext.ran = assembled.ran;
            sacchContext.fs_start = assembled.first_sample;
            sacchContext.superframe_start = assembled.first_sample;
            pdu = nxdn.parseLayer3(assembled.layer3_bits, sacchContext);
            [state, pdus] = appendWithSession(state, pdus, pdu);
        end
    end
end

halfRanges = {[c.half1BitStart c.half1BitEnd], ...
    [c.half2BitStart c.half2BitEnd]};
halfTypes = {frameInfo.half1_type, frameInfo.half2_type};
framePayloads = {};
for half = 1:2
    if ~strcmp(halfTypes{half}, 'FACCH1'), continue; end
    range = halfRanges{half};
    block = nxdn.decodeFacch1(frameBits(range(1):range(2)), half);
    fr.facch1_count = fr.facch1_count + 1;
    fr.facch1_ok_count = fr.facch1_ok_count + double(block.ok);
    state = appendBlock(state, block, fsStart, half);
    if block.ok
        payloadHex = nxdn.bitsToHex(block.layer3_bits);
        if any(strcmp(framePayloads, payloadHex)), continue; end
        framePayloads{end+1} = payloadHex; %#ok<AGROW>
        facchContext = context;
        facchContext.functional_channel = 'FACCH1';
        facchContext.half_index = half;
        facchContext.ran = state.lastRan;
        pdu = nxdn.parseLayer3(block.layer3_bits, facchContext);
        [state, pdus] = appendWithSession(state, pdus, pdu);
    end
end

if any(strcmp(frameInfo.functional_channel, {'UDCH', 'FACCH2'}))
    block = nxdn.decodeUdchFacch2( ...
        frameBits(17:364), frameInfo.functional_channel);
    fr.data_ok = block.ok;
    state = appendBlock(state, block, fsStart, 0);
    if block.ok
        state.lastRan = block.ran;
        context.ran = state.lastRan;
        pdu = nxdn.parseLayer3(block.layer3_bits, context);
        [state, pdus] = appendWithSession(state, pdus, pdu);
    end
elseif startsWith(frameInfo.functional_channel, 'CAC_')
    if strcmp(frameInfo.functional_channel, 'CAC_OUTBOUND')
        physical = frameBits(17:316);
    else
        physical = frameBits(17:268);
    end
    block = nxdn.decodeCac(physical, frameInfo.functional_channel);
    fr.data_ok = block.ok;
    state = appendBlock(state, block, fsStart, 0);
    if block.ok
        state.lastRan = block.ran;
        context.ran = state.lastRan;
        pdu = nxdn.parseLayer3(block.layer3_bits, context);
        [state, pdus] = appendWithSession(state, pdus, pdu);
    end
end

fr.valid = fr.sacch_ok || fr.facch1_ok_count > 0 || fr.data_ok;
state = appendFrame(state, fr);
end

function state = appendFrame(state, frame)
state.frameCount = state.frameCount + uint64(1);
if frame.valid
    state.validFrameCount = state.validFrameCount + uint64(1);
    state.validSyncScoreSum = state.validSyncScoreSum + frame.sync_score;
end
if state.retainDiagnostics
    state.frames(end+1, 1) = frame;
end
end

function state = appendBlock(state, block, fsStart, halfIndex)
state.channelBlockCount = state.channelBlockCount + uint64(1);
state.validChannelBlockCount = state.validChannelBlockCount + ...
    uint64(logical(block.ok));
if ~state.retainDiagnostics, return; end
item = state.blockTemplate;
item.channel = block.channel;
item.fs_start = fsStart;
item.half_index = halfIndex;
item.ok = block.ok;
item.crc_ok = block.crc_ok;
item.tail_ok = block.tail_ok;
if isfield(block, 'ran'), item.ran = block.ran; end
item.metric = block.codec.viterbi.normalized_metric;
if isfield(block, 'layer3_bits')
    item.payload_hex = nxdn.bitsToHex(block.layer3_bits);
end
state.blocks(end+1, 1) = item;
end

function context = makeContext(frameInfo, lich, fsStart, frameIndex, ran)
context = struct('ran', ran, 'rf_channel_type', frameInfo.rf_channel_type, ...
    'functional_channel', frameInfo.functional_channel, ...
    'direction', frameInfo.direction, 'lich', lich, 'fs_start', fsStart, ...
    'frame_index', frameIndex, 'half_index', [], 'superframe_start', [], ...
    'voice_present', frameInfo.voice_present, ...
    'voice_half_mask', [strcmp(frameInfo.half1_type, 'VCH'), ...
        strcmp(frameInfo.half2_type, 'VCH')]);
end

function [state, pdus] = appendWithSession(state, pdus, pdu)
if isempty(pdu), return; end
pdus = appendPdu(pdus, pdu);
[state.session, call] = nxdn.sessionFeed( ...
    state.session, pdu, state.cfg);
pdus = appendPdu(pdus, call);
state.pduCount = state.pduCount + uint64(1 + double(~isempty(call)));
end

function out = appendPdu(arr, item)
if isempty(item)
    out = arr;
elseif isempty(arr)
    out = item;
else
    out = arr;
    out(end+1) = item;
end
end
