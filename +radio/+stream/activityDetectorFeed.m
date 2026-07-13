function [detector, result] = activityDetectorFeed(detector, chunk)
%ACTIVITYDETECTORFEED Update activity state from one contiguous IqChunk.
radio.stream.validateIqChunk(chunk);
if chunk.sampleRateHz ~= detector.sampleRateHz
    error('radio:stream:activityDetectorFeed:SampleRate', ...
        'Chunk and activity detector sample rates differ.');
end

durationSec = numel(chunk.iq) / detector.sampleRateHz;
if isempty(chunk.iq)
    powerDb = detector.config.minPowerDb;
else
    meanPower = mean(abs(double(chunk.iq)).^2);
    powerDb = max(detector.config.minPowerDb, 10 * log10(max(meanPower, realmin)));
end
detector.lastPowerDb = powerDb;
detector.lastSampleEnd = chunk.sourceSampleEnd;
onThresholdDb = detector.noiseFloorDb + detector.config.onMarginDb;
offThresholdDb = detector.noiseFloorDb + detector.config.offMarginDb;
started = false;
ended = false;

if ~detector.isActive
    if powerDb > onThresholdDb
        if ~strcmp(detector.phase, 'pending_on')
            detector.phase = 'pending_on';
            detector.onDurationSec = 0;
            detector.candidateStartSample = chunk.sourceSampleStart;
        end
        detector.onDurationSec = detector.onDurationSec + durationSec;
        if detector.onDurationSec >= detector.config.minOnSec
            detector.phase = 'active';
            detector.isActive = true;
            detector.offDurationSec = 0;
            started = true;
        end
    else
        detector.phase = 'inactive';
        detector.onDurationSec = 0;
        alpha = detector.config.noiseUpdateAlpha;
        detector.noiseFloorDb = (1 - alpha) * detector.noiseFloorDb + ...
            alpha * powerDb;
    end
else
    if powerDb < offThresholdDb
        detector.phase = 'pending_off';
        detector.offDurationSec = detector.offDurationSec + durationSec;
        if detector.offDurationSec >= detector.config.offHangSec
            detector.phase = 'inactive';
            detector.isActive = false;
            detector.onDurationSec = 0;
            detector.offDurationSec = 0;
            ended = true;
        end
    else
        detector.phase = 'active';
        detector.offDurationSec = 0;
    end
end

result = struct( ...
    'phase', detector.phase, ...
    'isActive', detector.isActive, ...
    'started', started, ...
    'ended', ended, ...
    'powerDb', powerDb, ...
    'noiseFloorDb', detector.noiseFloorDb, ...
    'onThresholdDb', detector.noiseFloorDb + detector.config.onMarginDb, ...
    'offThresholdDb', detector.noiseFloorDb + detector.config.offMarginDb, ...
    'candidateStartSample', detector.candidateStartSample);
end
