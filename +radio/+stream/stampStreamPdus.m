function pdus = stampStreamPdus(pdus, protocol, snapshot, epochId)
%STAMPSTREAMPDUS Add absolute source-sample metadata to decoded PDUs.
pdus = radio.normalizePdus(pdus);
if isempty(pdus), return; end
protocol = radio.normalizeProtocolNames({protocol});
protocol = protocol{1};
targetSampleRateHz = targetRate(protocol, snapshot.sampleRateHz);

for k = 1:numel(pdus)
    [localSeconds, basis] = localPosition(pdus(k), targetSampleRateHz);
    sourceOffset = max(0, round(localSeconds * snapshot.sampleRateHz));
    sourceSample = snapshot.sourceSampleStart + uint64(sourceOffset);
    if snapshot.sourceSampleEnd > snapshot.sourceSampleStart
        sourceSample = min(sourceSample, snapshot.sourceSampleEnd - uint64(1));
    end
    stream = struct( ...
        'epoch_id', uint64(epochId), ...
        'source_sample', sourceSample, ...
        'source_time_sec', double(sourceSample) / snapshot.sampleRateHz, ...
        'window_start_source_sample', snapshot.sourceSampleStart, ...
        'window_end_source_sample', snapshot.sourceSampleEnd, ...
        'position_basis', basis);
    pdus(k).extra.stream = stream;
end
end

function [seconds, basis] = localPosition(pdu, targetSampleRateHz)
fsStart = radio.getNestedField(pdu, 'extra.fs_start', []);
if isnumeric(fsStart) && isscalar(fsStart) && isfinite(fsStart)
    seconds = max(0, double(fsStart) / targetSampleRateHz);
    basis = 'extra.fs_start';
    return;
end
startSample = radio.getNestedField(pdu, 'extra.start_sample', []);
if isnumeric(startSample) && isscalar(startSample) && isfinite(startSample)
    seconds = max(0, double(startSample) / targetSampleRateHz);
    basis = 'extra.start_sample';
    return;
end
startTimeSec = radio.getNestedField(pdu, 'extra.start_time_s', []);
if isnumeric(startTimeSec) && isscalar(startTimeSec) && isfinite(startTimeSec)
    seconds = max(0, double(startTimeSec));
    basis = 'extra.start_time_s';
    return;
end
seconds = 0;
basis = 'window_start_fallback';
end

function sampleRateHz = targetRate(protocol, fallback)
specs = radio.protocolRegistry();
idx = find(strcmp({specs.name}, protocol), 1);
if isempty(idx)
    sampleRateHz = fallback;
else
    sampleRateHz = specs(idx).targetSampleRateHz;
end
end
