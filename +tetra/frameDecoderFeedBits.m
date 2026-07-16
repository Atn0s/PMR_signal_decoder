function [state, pdus, diagnostics] = frameDecoderFeedBits( ...
        state, bits, bitValidMask, varargin)
%FRAMEDECODERFEEDBITS Decode newly complete TETRA DMO slots from a bit view.
if state.finalized
    error('tetra:frameDecoderFeedBits:Finalized', ...
        'Cannot feed a finalized TETRA frame decoder.');
end
p = inputParser;
p.addParameter('BitOffset', 0);
p.addParameter('MinimumSlotStartBit', -inf);
p.addParameter('DecodeContext', struct());
p.parse(varargin{:});
bits = logical(bits(:));
if isempty(bitValidMask) || numel(bitValidMask) ~= numel(bits)
    bitValidMask = true(size(bits));
else
    bitValidMask = logical(bitValidMask(:));
end

training = tetra.findTrainingSequences( ...
    bits, state.sequences, state.cfg);
[slotReport, state.dmoContext] = tetra.inferDmoBursts( ...
    bits, training, state.sequences, state.cfg, bitValidMask, ...
    'BitOffset', p.Results.BitOffset, ...
    'MinimumSlotStartBit', p.Results.MinimumSlotStartBit, ...
    'InitialContext', state.dmoContext);
decodeContext = p.Results.DecodeContext;
decodeContext.emitSessions = false;
events = tetra.pdusFromSlotReport( ...
    slotReport, state.cfg, decodeContext);
[state.sessionState, summaries] = ...
    tetra.sessionDecoderFeed(state.sessionState, events);
pdus = appendPdus(events, summaries);
pdus = sortForStreaming(pdus);

state.candidateCount = state.candidateCount + ...
    uint64(slotReport.candidateCount);
state.confirmedBurstCount = state.confirmedBurstCount + ...
    uint64(slotReport.confirmedCount);
strongTypes = {'TETRA_DMAC_SYNC', 'TETRA_STCH', 'TETRA_SCHF'};
if isempty(events)
    strongCount = 0;
else
    strongCount = nnz(ismember({events.type}, strongTypes));
end
state.validControlPduCount = state.validControlPduCount + ...
    uint64(strongCount);
state.decodedPduCount = state.decodedPduCount + uint64(numel(pdus));
diagnostics = struct( ...
    'training', training, ...
    'slots', slotReport, ...
    'streamTotals', tetra.frameDecoderReport(state));
pdus = radio.normalizePdus(pdus);
end

function values = appendPdus(values, items)
if isempty(items), return; end
if isempty(values), values = items; else, values(end+1:end+numel(items)) = items; end
end

function pdus = sortForStreaming(pdus)
if isempty(pdus), return; end
times = zeros(numel(pdus), 1);
for k = 1:numel(pdus)
    if strcmp(char(pdus(k).type), 'TETRA_SESSION')
        times(k) = radio.getNestedField(pdus(k), ...
            'extra.end_time_s', inf);
    else
        times(k) = radio.getNestedField(pdus(k), ...
            'extra.start_time_s', inf);
    end
end
[~, order] = sortrows([times, (1:numel(pdus)).']);
pdus = pdus(order);
end
