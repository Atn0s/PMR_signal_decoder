function [scanner, output] = multiStreamScannerFeed(scanner, widebandChunk)
%MULTISTREAMSCANNERFEED Send one input block to every selected carrier.
if scanner.finalized
    error('radio:tuned:multiStreamScannerFeed:Finalized', ...
        'A finalized multi-carrier scanner cannot accept more input.');
end
radio.stream.validateIqChunk(widebandChunk);
if widebandChunk.sampleRateHz ~= scanner.inputSampleRateHz
    error('radio:tuned:multiStreamScannerFeed:SampleRate', ...
        'Wideband input sample rate changed.');
end
if widebandChunk.centerFrequencyHz ~= scanner.inputCenterFrequencyHz
    error('radio:tuned:multiStreamScannerFeed:CenterFrequency', ...
        'Retuning requires a new multi-carrier scanner.');
end

feedToken = tic;
channelOutputs = cell(scanner.channelCount, 1);
newPdus = struct([]);
closedEpochs = repmat(radio.stream.newEpoch(0, 0, 0, 0), 0, 1);
basebandChunks = cell(scanner.channelCount, 1);
channelElapsedSec = zeros(scanner.channelCount, 1);
ddcToken = tic;
if scanner.useFusedDdc
    [scanner.fusedDdc, basebandChunks] = ...
        radio.tuned.multiDdcFeed(scanner.fusedDdc, widebandChunk);
end
ddcElapsedSec = toc(ddcToken);
deferLockedDecode = shouldDeferLockedDecode(scanner);
for k = 1:scanner.channelCount
    scanner.channels{k}.coordinator.deferLockedDecode = deferLockedDecode;
end
for k = 1:scanner.channelCount
    channelToken = tic;
    if scanner.useFusedDdc
        basebandChunk = [];
        if k <= numel(basebandChunks), basebandChunk = basebandChunks{k}; end
        [scanner.channels{k}, channelOutputs{k}] = ...
            radio.tuned.streamScannerFeedBaseband( ...
                scanner.channels{k}, widebandChunk, basebandChunk);
    else
        [scanner.channels{k}, channelOutputs{k}] = ...
            radio.tuned.streamScannerFeed(scanner.channels{k}, widebandChunk);
        ddcElapsedSec = ddcElapsedSec + toc(channelToken);
    end
    channelElapsedSec(k) = toc(channelToken);
    newPdus = appendStruct(newPdus, channelOutputs{k}.newPdus);
    closedEpochs = appendStruct( ...
        closedEpochs, channelOutputs{k}.closedEpochs);
end
scanner.pdus = appendStruct(scanner.pdus, newPdus);
scanner.closedEpochs = appendStruct(scanner.closedEpochs, closedEpochs);
scanner.lastOutputs = channelOutputs;
scanner.feedCount = scanner.feedCount + uint64(1);
scanner.inputSampleCount = scanner.inputSampleCount + ...
    uint64(numel(widebandChunk.iq));
scanner.lastDdcElapsedSec = ddcElapsedSec;
scanner.maxDdcElapsedSec = max(scanner.maxDdcElapsedSec, ddcElapsedSec);
scanner.totalDdcElapsedSec = scanner.totalDdcElapsedSec + ddcElapsedSec;
scanner.lastFeedElapsedSec = toc(feedToken);
if scanner.lastFeedElapsedSec > scanner.maxFeedElapsedSec
    scanner.maxFeedElapsedSec = scanner.lastFeedElapsedSec;
    dispatch = cell(scanner.channelCount, 1);
    for channelIndex = 1:scanner.channelCount
        dispatch{channelIndex} = radio.getNestedField( ...
            channelOutputs{channelIndex}, ...
            'coordinator.decoder.dispatch', struct());
    end
    scanner.maxFeedBreakdown = struct( ...
        'feedIndex', scanner.feedCount, ...
        'ddcElapsedSec', ddcElapsedSec, ...
        'channelElapsedSec', channelElapsedSec, ...
        'decoderDispatch', {dispatch}, ...
        'states', {cellfun(@(item) item.state, channelOutputs, ...
            'UniformOutput', false)}, ...
        'selectedProtocols', {cellfun(@(item) item.selectedProtocol, ...
            channelOutputs, 'UniformOutput', false)});
end
scanner.totalFeedElapsedSec = scanner.totalFeedElapsedSec + ...
    scanner.lastFeedElapsedSec;

output = struct( ...
    'channelOutputs', {channelOutputs}, ...
    'states', {cellfun(@(item) item.state, channelOutputs, ...
        'UniformOutput', false)}, ...
    'selectedProtocols', {cellfun(@(item) item.selectedProtocol, ...
        channelOutputs, 'UniformOutput', false)}, ...
    'newPdus', newPdus, ...
    'closedEpochs', closedEpochs, ...
    'feedCount', scanner.feedCount, ...
    'inputSampleCount', scanner.inputSampleCount);
output.ddcElapsedSec = scanner.lastDdcElapsedSec;
output.feedElapsedSec = scanner.lastFeedElapsedSec;
output.useFusedDdc = scanner.useFusedDdc;
end

function tf = shouldDeferLockedDecode(scanner)
% Identification and winner catch-up have priority over steady-state work.
% Otherwise an early-locking carrier can continuously refill the process
% queue and starve a later (notably TETRA) winner on the same worker pool.
priorityStates = {'ACTIVITY_PENDING', 'CLASSIFYING', 'RECLASSIFYING', ...
    'CATCHING_UP'};
states = cell(scanner.channelCount, 1);
for k = 1:scanner.channelCount
    states{k} = scanner.channels{k}.coordinator.state;
end
tf = any(ismember(states, priorityStates));
end

function value = appendStruct(value, items)
if isempty(items), return; end
if isempty(value), value = items(:); else, value = [value(:); items(:)]; end
end
