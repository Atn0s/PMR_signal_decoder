function report = frameDecoderReport(state, candidates)
%FRAMEDECODERREPORT Build bounded or full NXDN frame diagnostics.
if nargin < 2 || isempty(candidates)
    candidates = repmat(struct('fs_start', 0, 'symbol_phase', 0, ...
        'polarity', 1, 'score', 0, 'frame_index', 0, ...
        'locked', false), 0, 1);
end
report = struct();
report.syncCandidates = candidates;
report.frames = state.frames;
report.channelBlocks = state.blocks;
report.lichHistogram = histogramStruct(state.lichValues);
report.pduCount = double(state.pduCount);
report.validFrameCount = double(state.validFrameCount);
report.validChannelBlockCount = double(state.validChannelBlockCount);
report.sacchAssemblyCount = double(state.sacchAssemblyCount);
report.quality = qualitySummary(state);
end

function out = histogramStruct(values)
out = repmat(struct('lich', 0, 'count', 0), 0, 1);
if isempty(values), return; end
[uniqueValues, ~, idx] = unique(values);
counts = accumarray(idx, 1);
for k = 1:numel(uniqueValues)
    out(end+1, 1) = struct( ...
        'lich', uniqueValues(k), 'count', counts(k)); %#ok<AGROW>
end
end

function quality = qualitySummary(state)
quality = struct( ...
    'sync_candidate_count', double(state.candidateCount), ...
    'lich_ok_count', double(state.lichOkCount), ...
    'valid_frame_ratio', 0, ...
    'channel_block_pass_ratio', 0, ...
    'mean_valid_sync_score', 0);
if state.frameCount > 0
    quality.valid_frame_ratio = ...
        double(state.validFrameCount) / double(state.frameCount);
end
if state.channelBlockCount > 0
    quality.channel_block_pass_ratio = ...
        double(state.validChannelBlockCount) / ...
        double(state.channelBlockCount);
end
if state.validFrameCount > 0
    quality.mean_valid_sync_score = ...
        state.validSyncScoreSum / double(state.validFrameCount);
end
end
