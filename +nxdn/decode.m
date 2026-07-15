function [pdus, report] = decode(y, cfg)
%DECODE Decode NXDN96 non-voice data PDUs from demodulated samples.
if nargin < 2 || isempty(cfg), cfg = nxdn.config(); end
candidates = nxdn.findFrameSync(y, cfg);
pdus = struct([]);
state = nxdn.frameDecoderInit(cfg, 'RetainDiagnostics', true);

for k = 1:numel(candidates)
    [state, framePdus] = nxdn.frameDecoderFeedCandidate( ...
        state, y, candidates(k));
    pdus = appendPdus(pdus, framePdus);
end
[state, finalPdus] = nxdn.frameDecoderFinalize(state);
pdus = appendPdus(pdus, finalPdus);
pdus = nxdn.postprocess(pdus);
report = nxdn.frameDecoderReport(state, candidates);
end

function out = appendPdus(arr, items)
if isempty(items)
    out = arr;
elseif isempty(arr)
    out = items;
else
    out = arr;
    out(end+1:end+numel(items)) = items;
end
end
