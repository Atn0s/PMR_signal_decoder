function [pdus, report] = decode(y, cfg)
%DECODE Decode NXDN96 non-voice data PDUs from demodulated samples.
if nargin < 2 || isempty(cfg), cfg = nxdn.config(); end
c = nxdn.constants();
candidates = nxdn.findFrameSync(y, cfg);
pdus = struct([]);
frames = repmat(emptyFrame(), 0, 1);
blocks = repmat(emptyBlock(), 0, 1);
sacchState = nxdn.sacchAssemblerInit();
session = nxdn.sessionInit();
lastRan = [];
lichValues = [];
sacchAssemblyCount = 0;

for k = 1:numel(candidates)
    [symbols, recovery] = nxdn.recoverFrameSymbols(y, candidates(k), cfg);
    if isempty(symbols), continue; end
    [dibits, ~, decisionError] = nxdn.sliceDibits(symbols);
    lich = nxdn.decodeLich(dibits(11:18), cfg);
    fr = emptyFrame();
    fr.fs_start = recovery.fsStart;
    fr.sync_score = recovery.fswScore;
    fr.mean_decision_error = mean(decisionError);
    fr.lich_ok = lich.ok;
    fr.lich = lich.value;
    if ~lich.ok
        frames(end+1, 1) = fr; %#ok<AGROW>
        continue;
    end
    frameInfo = nxdn.frameInfoFromLich(lich);
    fr.rf_channel_type = frameInfo.rf_channel_type;
    fr.functional_channel = frameInfo.functional_channel;
    fr.direction = frameInfo.direction;
    fr.voice_present = frameInfo.voice_present;
    fr.supported = frameInfo.supported;
    lichValues(end+1, 1) = lich.value; %#ok<AGROW>
    if ~frameInfo.supported
        frames(end+1, 1) = fr; %#ok<AGROW>
        continue;
    end
    scrambled = nxdn.descrambleDibits(dibits(11:192));
    frameBits = nxdn.dibitsToBits(scrambled);
    context = makeContext(frameInfo, lich.value, recovery.fsStart, k, lastRan);

    if frameInfo.sacch
        block = nxdn.decodeSacch(frameBits(c.sacchBitStart:c.sacchBitEnd), frameInfo);
        fr.sacch_ok = block.ok;
        blocks(end+1, 1) = blockSummary(block, recovery.fsStart, 0); %#ok<AGROW>
        if block.ok
            lastRan = block.ran;
            context.ran = lastRan;
            [sacchState, assembled] = nxdn.sacchAssemblerFeed( ...
                sacchState, block, frameInfo, recovery.fsStart, cfg);
            if ~isempty(assembled)
                sacchAssemblyCount = sacchAssemblyCount + 1;
                sacchContext = context;
                sacchContext.functional_channel = 'SACCH';
                sacchContext.ran = assembled.ran;
                sacchContext.fs_start = assembled.first_sample;
                sacchContext.superframe_start = assembled.first_sample;
                pdu = nxdn.parseLayer3(assembled.layer3_bits, sacchContext);
                [pdus, session] = appendWithSession(pdus, session, pdu, cfg);
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
        blocks(end+1, 1) = blockSummary(block, recovery.fsStart, half); %#ok<AGROW>
        if block.ok
            payloadHex = nxdn.bitsToHex(block.layer3_bits);
            if any(strcmp(framePayloads, payloadHex)), continue; end
            framePayloads{end+1} = payloadHex; %#ok<AGROW>
            facchContext = context;
            facchContext.functional_channel = 'FACCH1';
            facchContext.half_index = half;
            facchContext.ran = lastRan;
            pdu = nxdn.parseLayer3(block.layer3_bits, facchContext);
            [pdus, session] = appendWithSession(pdus, session, pdu, cfg);
        end
    end

    if any(strcmp(frameInfo.functional_channel, {'UDCH', 'FACCH2'}))
        block = nxdn.decodeUdchFacch2(frameBits(17:364), frameInfo.functional_channel);
        fr.data_ok = block.ok;
        blocks(end+1, 1) = blockSummary(block, recovery.fsStart, 0); %#ok<AGROW>
        if block.ok
            lastRan = block.ran;
            context.ran = lastRan;
            pdu = nxdn.parseLayer3(block.layer3_bits, context);
            [pdus, session] = appendWithSession(pdus, session, pdu, cfg);
        end
    elseif startsWith(frameInfo.functional_channel, 'CAC_')
        if strcmp(frameInfo.functional_channel, 'CAC_OUTBOUND')
            physical = frameBits(17:316);
        else
            physical = frameBits(17:268);
        end
        block = nxdn.decodeCac(physical, frameInfo.functional_channel);
        fr.data_ok = block.ok;
        blocks(end+1, 1) = blockSummary(block, recovery.fsStart, 0); %#ok<AGROW>
        if block.ok
            lastRan = block.ran;
            context.ran = lastRan;
            pdu = nxdn.parseLayer3(block.layer3_bits, context);
            [pdus, session] = appendWithSession(pdus, session, pdu, cfg);
        end
    end
    fr.valid = fr.sacch_ok || fr.facch1_ok_count > 0 || fr.data_ok;
    frames(end+1, 1) = fr; %#ok<AGROW>
end
[session, callPdu] = nxdn.sessionFinalize(session, cfg); %#ok<ASGLU>
pdus = appendPdu(pdus, callPdu);
pdus = nxdn.postprocess(pdus);
report = struct();
report.syncCandidates = candidates;
report.frames = frames;
report.channelBlocks = blocks;
report.lichHistogram = histogramStruct(lichValues);
report.pduCount = numel(pdus);
report.validFrameCount = nnz([frames.valid]);
report.validChannelBlockCount = nnz([blocks.ok]);
report.sacchAssemblyCount = sacchAssemblyCount;
report.quality = qualitySummary(candidates, frames, blocks);
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

function [pdus, session] = appendWithSession(pdus, session, pdu, cfg)
if isempty(pdu), return; end
pdus = appendPdu(pdus, pdu);
[session, call] = nxdn.sessionFeed(session, pdu, cfg);
pdus = appendPdu(pdus, call);
end

function out = appendPdu(arr, item)
if isempty(item), out = arr;
elseif isempty(arr), out = item;
else, out = arr; out(end+1) = item;
end
end

function item = emptyFrame()
item = struct('fs_start', 0, 'sync_score', 0, 'mean_decision_error', 0, ...
    'lich_ok', false, 'lich', 0, 'rf_channel_type', '', ...
    'functional_channel', '', 'direction', '', 'voice_present', false, ...
    'supported', false, 'sacch_ok', false, 'facch1_count', 0, ...
    'facch1_ok_count', 0, 'data_ok', false, 'valid', false);
end

function item = emptyBlock()
item = struct('channel', '', 'fs_start', 0, 'half_index', 0, 'ok', false, ...
    'crc_ok', false, 'tail_ok', false, 'ran', [], 'metric', inf, ...
    'payload_hex', '');
end

function item = blockSummary(block, fsStart, halfIndex)
item = emptyBlock();
item.channel = block.channel;
item.fs_start = fsStart;
item.half_index = halfIndex;
item.ok = block.ok;
item.crc_ok = block.crc_ok;
item.tail_ok = block.tail_ok;
if isfield(block, 'ran'), item.ran = block.ran; end
item.metric = block.codec.viterbi.normalized_metric;
if isfield(block, 'layer3_bits'), item.payload_hex = nxdn.bitsToHex(block.layer3_bits); end
end

function out = histogramStruct(values)
out = repmat(struct('lich', 0, 'count', 0), 0, 1);
if isempty(values), return; end
[uniqueValues, ~, idx] = unique(values);
counts = accumarray(idx, 1);
for k = 1:numel(uniqueValues)
    out(end+1, 1) = struct('lich', uniqueValues(k), 'count', counts(k)); %#ok<AGROW>
end
end

function quality = qualitySummary(candidates, frames, blocks)
quality = struct('sync_candidate_count', numel(candidates), ...
    'lich_ok_count', 0, 'valid_frame_ratio', 0, ...
    'channel_block_pass_ratio', 0, 'mean_valid_sync_score', 0);
if ~isempty(frames)
    quality.lich_ok_count = nnz([frames.lich_ok]);
    quality.valid_frame_ratio = nnz([frames.valid]) / numel(frames);
    valid = frames([frames.valid]);
    if ~isempty(valid), quality.mean_valid_sync_score = mean([valid.sync_score]); end
end
if ~isempty(blocks)
    quality.channel_block_pass_ratio = nnz([blocks.ok]) / numel(blocks);
end
end
