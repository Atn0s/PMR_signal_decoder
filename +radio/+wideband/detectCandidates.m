function [detections, report] = detectCandidates(batch, varargin)
%DETECTCANDIDATES Find fine carrier candidates inside active PFB subbands.
p = inputParser;
p.addParameter('Config', radio.wideband.defaultConfig());
p.addParameter('ExistingTracks', radio.wideband.emptyTrack());
p.parse(varargin{:});
cfg = p.Results.Config.detector;
existingTracks = p.Results.ExistingTracks;
if isscalar(existingTracks) && existingTracks.trackId == 0
    existingTracks = existingTracks([]);
end

empty = emptyDetection();
detections = empty([]);
frameCount = size(batch.iq, 2);
if frameCount == 0
    report = makeReport([], [], NaN, NaN, NaN, frameCount, detections);
    return;
end

powerLinear = mean(abs(batch.iq) .^ 2, 2);
powerDb = 10 .* log10(double(powerLinear) + 1e-12);
noiseFloorDb = median(powerDb(isfinite(powerDb)));
if isempty(noiseFloorDb), noiseFloorDb = cfg.minPowerDb; end
thresholdDb = max(cfg.minPowerDb, noiseFloorDb + cfg.onMarginDb);
activeBins = find(powerDb >= thresholdDb);
offThresholdDb = max(cfg.minPowerDb, noiseFloorDb + cfg.offMarginDb);
for trackIndex = 1:numel(existingTracks)
    bin = double(existingTracks(trackIndex).coarseBin);
    if bin >= 1 && bin <= numel(powerDb) && powerDb(bin) >= offThresholdDb
        activeBins(end+1, 1) = bin; %#ok<AGROW>
    end
end
activeBins = unique(activeBins);

fineCfg = radio.defaultConfig();
fineCfg.psdPeakThresholdDb = cfg.finePsdThresholdDb;
fineCfg.psdNperseg = min(cfg.fineFftLength, frameCount);
fineCfg.psdChannelSmoothingHz = cfg.channelSmoothingHz;
fineCfg.psdCandidateMinSpacingHz = cfg.candidateMinSpacingHz;
fineCfg.psdMaxCandidates = inf;

for index = 1:numel(activeBins)
    bin = activeBins(index);
    localIq = batch.iq(bin, :).';
    offsets = radio.psdBlindSearch(localIq, batch.sampleRateHz, fineCfg);
    if isempty(offsets)
        offsets = fallbackOffset(localIq, batch.sampleRateHz, ...
            fineCfg.psdNperseg);
    end
    for localOffsetHz = offsets
        absoluteOffsetHz = batch.binCenterOffsetHz(bin) + localOffsetHz;
        item = empty;
        item.frequencyOffsetHz = double(absoluteOffsetHz);
        item.centerFrequencyHz = double( ...
            batch.widebandCenterFrequencyHz + absoluteOffsetHz);
        item.coarseBin = uint32(bin);
        item.coarseCenterOffsetHz = double(batch.binCenterOffsetHz(bin));
        item.residualOffsetHz = double(localOffsetHz);
        item.powerDb = double(powerDb(bin));
        item.noiseFloorDb = double(noiseFloorDb);
        item.snrDb = double(powerDb(bin) - noiseFloorDb);
        item.outputSampleStart = uint64(batch.outputSampleStart);
        item.outputSampleEnd = uint64(batch.outputSampleEnd);
        item.widebandStartSample = firstSourceSample(batch);
        item.widebandEndSample = lastSourceSample(batch);
        item.continuityGeneration = uint64(batch.continuityGeneration);
        detections(end+1, 1) = item; %#ok<AGROW>
    end
end

detections = mergeDuplicates(detections, cfg.duplicateMergeHz);
if isfinite(cfg.maxCandidatesPerBatch) && ...
        numel(detections) > cfg.maxCandidatesPerBatch
    [~, order] = sort([detections.snrDb], 'descend');
    detections = detections(order(1:cfg.maxCandidatesPerBatch));
end
if ~isempty(detections)
    [~, order] = sort([detections.frequencyOffsetHz]);
    detections = detections(order);
end
report = makeReport(powerDb, activeBins, noiseFloorDb, thresholdDb, ...
    offThresholdDb, ...
    frameCount, detections);
end

function offset = fallbackOffset(iq, sampleRateHz, nfft)
[f, psd] = common.welchPsd(iq, sampleRateHz, nfft);
if isempty(psd)
    offset = zeros(1, 0);
    return;
end
[~, index] = max(psd);
offset = f(index);
end

function detections = mergeDuplicates(detections, toleranceHz)
if numel(detections) < 2
    return;
end
[~, order] = sort([detections.frequencyOffsetHz]);
detections = detections(order);
merged = detections([]);
index = 1;
while index <= numel(detections)
    groupEnd = index;
    while groupEnd < numel(detections) && ...
            detections(groupEnd + 1).frequencyOffsetHz - ...
            detections(groupEnd).frequencyOffsetHz <= toleranceHz
        groupEnd = groupEnd + 1;
    end
    group = detections(index:groupEnd);
    [~, best] = max([group.snrDb]);
    selected = group(best);
    weights = 10 .^ (([group.snrDb] - max([group.snrDb])) ./ 10);
    selected.frequencyOffsetHz = sum( ...
        [group.frequencyOffsetHz] .* weights) ./ sum(weights);
    selected.centerFrequencyHz = selected.centerFrequencyHz + ...
        selected.frequencyOffsetHz - group(best).frequencyOffsetHz;
    selected.residualOffsetHz = selected.frequencyOffsetHz - ...
        selected.coarseCenterOffsetHz;
    merged(end+1, 1) = selected; %#ok<AGROW>
    index = groupEnd + 1;
end
detections = merged;
end

function sample = firstSourceSample(batch)
if isempty(batch.frameSourceSamples)
    sample = uint64(0);
else
    sample = uint64(max(0, round(batch.frameSourceSamples(1))));
end
end

function sample = lastSourceSample(batch)
if isempty(batch.frameSourceSamples)
    sample = uint64(0);
else
    sample = uint64(max(0, round(batch.frameSourceSamples(end) + ...
        batch.widebandSampleRateHz / batch.sampleRateHz)));
end
end

function item = emptyDetection()
item = struct( ...
    'frequencyOffsetHz', 0.0, ...
    'centerFrequencyHz', 0.0, ...
    'coarseBin', uint32(0), ...
    'coarseCenterOffsetHz', 0.0, ...
    'residualOffsetHz', 0.0, ...
    'powerDb', -inf, ...
    'noiseFloorDb', -inf, ...
    'snrDb', 0.0, ...
    'outputSampleStart', uint64(0), ...
    'outputSampleEnd', uint64(0), ...
    'widebandStartSample', uint64(0), ...
    'widebandEndSample', uint64(0), ...
    'continuityGeneration', uint64(0));
end

function report = makeReport(powerDb, activeBins, noiseFloorDb, ...
        thresholdDb, offThresholdDb, frameCount, detections)
report = struct( ...
    'frameCount', double(frameCount), ...
    'powerDb', powerDb, ...
    'activeBins', uint32(activeBins(:)), ...
    'noiseFloorDb', double(noiseFloorDb), ...
    'thresholdDb', double(thresholdDb), ...
    'offThresholdDb', double(offThresholdDb), ...
    'candidateCount', numel(detections));
end
