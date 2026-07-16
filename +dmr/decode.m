function pdus = decode(y, cfg)
%DECODE Native MATLAB DMR metadata decode.
if nargin < 2 || isempty(cfg), cfg = dmr.config(); end
positions = dmr.findSyncPositions(y, cfg);
state = dmr.frameDecoderInit(cfg);
pdus = struct([]);
for index = 1:height(positions)
    [state, items] = dmr.frameDecoderFeedCandidate( ...
        state, y, positions.center(index), positions.polarity(index), ...
        char(positions.syncType(index)));
    pdus = appendPdus(pdus, items);
end
[state, items] = dmr.frameDecoderFinalize(state); %#ok<ASGLU>
pdus = appendPdus(pdus, items);
pdus = radio.normalizePdus(pdus);
end

function value = appendPdus(value, items)
if isempty(items), return; end
if isempty(value)
    value = items;
else
    value(end+1:end+numel(items)) = items;
end
end
