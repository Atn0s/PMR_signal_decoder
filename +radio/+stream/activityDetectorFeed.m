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
detector.samplesSinceSpectralNoise = ...
    detector.samplesSinceSpectralNoise + uint64(numel(chunk.iq));
if chunk.discontinuity
    detector.samplesSinceSpectralNoise = ...
        detector.spectralNoiseUpdateSamples;
end
spectralNoiseUpdated = detector.config.spectralNoiseEnabled && ...
    ~detector.hasExternalNoisePrior && ...
    (~detector.noiseFloorInitialized || ...
     detector.samplesSinceSpectralNoise >= ...
        detector.spectralNoiseUpdateSamples);
instantaneousNoiseFloorDb = NaN;
spectralNoiseValid = false;
if spectralNoiseUpdated
    [instantaneousNoiseFloorDb, spectralNoiseValid] = ...
        estimateSpectralNoiseFloor(chunk.iq, detector.config);
    if spectralNoiseValid
        detector.samplesSinceSpectralNoise = uint64(0);
        detector.spectralEstimateCount = ...
            detector.spectralEstimateCount + uint64(1);
        detector.lastInstantaneousNoiseFloorDb = ...
            instantaneousNoiseFloorDb;
    end
end
if detector.hasExternalNoisePrior
    % A finite caller-provided value is an explicit calibrated/tracker
    % prior.  Preserve that contract for short or spectrally dense signals;
    % the automatic estimator is authoritative only when no prior exists.
    decisionNoiseFloorDb = detector.noiseFloorDb;
    noiseFloorSource = 'external_prior';
elseif spectralNoiseValid
    decisionNoiseFloorDb = instantaneousNoiseFloorDb;
    noiseFloorSource = 'spectral';
elseif detector.noiseFloorInitialized
    decisionNoiseFloorDb = detector.noiseFloorDb;
    noiseFloorSource = 'temporal';
else
    % A very short first chunk cannot support a spectral estimate.  Treat it
    % as noise rather than inventing an absolute receiver-power threshold.
    decisionNoiseFloorDb = powerDb;
    noiseFloorSource = 'short_chunk_bootstrap';
end
spectralNoiseTriggered = false;
if ~detector.hasExternalNoisePrior && ~spectralNoiseUpdated && ...
        ~detector.isActive && detector.noiseFloorInitialized && ...
        powerDb > decisionNoiseFloorDb + detector.config.onMarginDb
    [triggeredFloorDb, triggeredValid] = ...
        estimateSpectralNoiseFloor(chunk.iq, detector.config);
    if triggeredValid
        instantaneousNoiseFloorDb = triggeredFloorDb;
        spectralNoiseValid = true;
        spectralNoiseUpdated = true;
        spectralNoiseTriggered = true;
        detector.samplesSinceSpectralNoise = uint64(0);
        detector.spectralEstimateCount = ...
            detector.spectralEstimateCount + uint64(1);
        detector.lastInstantaneousNoiseFloorDb = triggeredFloorDb;
        decisionNoiseFloorDb = triggeredFloorDb;
        noiseFloorSource = 'spectral_triggered';
    end
end
decisionNoiseFloorDb = max( ...
    detector.config.minPowerDb, decisionNoiseFloorDb);
snrDb = powerDb - decisionNoiseFloorDb;
detector.lastSnrDb = snrDb;
onThresholdDb = decisionNoiseFloorDb + detector.config.onMarginDb;
offThresholdDb = decisionNoiseFloorDb + detector.config.offMarginDb;
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
        detector = updateNoiseFloor(detector, ...
            decisionNoiseFloorDb, spectralNoiseValid);
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

% Initialize/report the smoothed floor even when the first chunk already
% contains a valid narrowband signal.  The robust spectral estimate uses
% unoccupied bins, so this does not require a leading-silence calibration
% interval and does not move candidateStartSample back to file time zero.
if ~detector.noiseFloorInitialized && spectralNoiseValid
    detector.noiseFloorDb = decisionNoiseFloorDb;
    detector.noiseFloorInitialized = true;
end

result = struct( ...
    'phase', detector.phase, ...
    'isActive', detector.isActive, ...
    'started', started, ...
    'ended', ended, ...
    'powerDb', powerDb, ...
    'noiseFloorDb', decisionNoiseFloorDb, ...
    'smoothedNoiseFloorDb', detector.noiseFloorDb, ...
    'instantaneousNoiseFloorDb', instantaneousNoiseFloorDb, ...
    'spectralNoiseValid', spectralNoiseValid, ...
    'spectralNoiseUpdated', spectralNoiseUpdated, ...
    'spectralNoiseTriggered', spectralNoiseTriggered, ...
    'spectralEstimateCount', detector.spectralEstimateCount, ...
    'noiseFloorSource', noiseFloorSource, ...
    'snrDb', snrDb, ...
    'onThresholdDb', onThresholdDb, ...
    'offThresholdDb', offThresholdDb, ...
    'candidateStartSample', detector.candidateStartSample);
end

function detector = updateNoiseFloor( ...
        detector, decisionNoiseFloorDb, spectralNoiseValid)
if ~detector.noiseFloorInitialized
    detector.noiseFloorDb = decisionNoiseFloorDb;
    detector.noiseFloorInitialized = true;
    return;
end
if ~spectralNoiseValid
    return;
end
alpha = detector.config.noiseUpdateAlpha;
detector.noiseFloorDb = (1 - alpha) * detector.noiseFloorDb + ...
    alpha * decisionNoiseFloorDb;
end

function [noiseFloorDb, valid] = estimateSpectralNoiseFloor(iq, cfg)
% Estimate complex-noise variance from bins not occupied by a PMR carrier.
% For white complex Gaussian noise, each periodogram bin is exponential and
% median(P)/log(2) is an unbiased estimate of the mean noise power.  PMR
% carriers occupy less than half of the selected baseband, so the median is
% robust even when activity begins in the first input chunk.
noiseFloorDb = NaN;
valid = false;
if ~cfg.spectralNoiseEnabled || numel(iq) < cfg.noiseMinSamples
    return;
end

fftLength = min(double(cfg.noiseFftLength), numel(iq));
if fftLength < cfg.noiseMinSamples
    return;
end
segmentCount = min(double(cfg.noiseMaxSegments), ...
    max(1, floor(numel(iq) / fftLength)));
lastStart = numel(iq) - fftLength + 1;
if segmentCount == 1
    starts = 1;
else
    starts = round(linspace(1, lastStart, segmentCount));
end

n = (0:fftLength-1).';
window = 0.5 - 0.5 .* cos(2 .* pi .* n ./ max(1, fftLength - 1));
windowPower = sum(window .^ 2);
segmentNoise = zeros(segmentCount, 1);
for k = 1:segmentCount
    first = starts(k);
    values = double(iq(first:first + fftLength - 1));
    spectrum = fft(values .* window, fftLength);
    periodogram = abs(spectrum) .^ 2 ./ max(windowPower, realmin);
    segmentNoise(k) = median(periodogram) ./ log(2);
end
noisePower = median(segmentNoise);
if ~isfinite(noisePower) || noisePower < 0
    return;
end
noiseFloorDb = max(cfg.minPowerDb, ...
    10 .* log10(max(noisePower, realmin)));
valid = true;
end
