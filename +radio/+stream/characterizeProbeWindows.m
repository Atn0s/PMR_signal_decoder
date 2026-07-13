function report = characterizeProbeWindows(iq, sampleRateHz, protocol, varargin)
%CHARACTERIZEPROBEWINDOWS Sweep probe start, duration, SNR, and frequency offset.
% Added AWGN is a relative stress test unless the input contains a calibrated
% clean reference signal.
p = inputParser;
p.addParameter('StartOffsetsSec', 0);
p.addParameter('WindowDurationsSec', []);
p.addParameter('SnrDb', inf);
p.addParameter('FrequencyOffsetsHz', 0);
p.addParameter('BaseSourceSample', uint64(0));
p.addParameter('RandomSeed', 1);
p.addParameter('RandomSeeds', []);
p.addParameter('ProbeFcn', []);
p.addParameter('StopAfterFirstConfirmation', true);
p.parse(varargin{:});

validateattributes(sampleRateHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
protocol = radio.normalizeProtocolNames({protocol});
protocol = protocol{1};
probe = radio.stream.probeRegistry({protocol});
if isempty(probe)
    error('radio:stream:characterizeProbeWindows:Protocol', ...
        'Protocol does not have a registered probe: %s', protocol);
end

durations = p.Results.WindowDurationsSec;
if isempty(durations)
    durations = progressiveWindows(probe);
end
durations = unique(sort(double(durations(:).')));
if isempty(durations) || any(~isfinite(durations)) || any(durations <= 0)
    error('radio:stream:characterizeProbeWindows:Durations', ...
        'WindowDurationsSec must contain positive finite values.');
end
offsets = double(p.Results.StartOffsetsSec(:).');
snrValues = double(p.Results.SnrDb(:).');
frequencyOffsets = double(p.Results.FrequencyOffsetsHz(:).');
randomSeeds = p.Results.RandomSeeds;
if isempty(randomSeeds)
    randomSeeds = p.Results.RandomSeed;
end
randomSeeds = double(randomSeeds(:).');
if isempty(randomSeeds) || any(~isfinite(randomSeeds)) || ...
        any(randomSeeds < 0) || any(mod(randomSeeds, 1) ~= 0)
    error('radio:stream:characterizeProbeWindows:RandomSeeds', ...
        'RandomSeeds must contain finite nonnegative integers.');
end
if any(~isfinite(offsets)) || any(offsets < 0)
    error('radio:stream:characterizeProbeWindows:Offsets', ...
        'StartOffsetsSec must contain finite nonnegative values.');
end

savedRng = rng;
rngCleanup = onCleanup(@() rng(savedRng));
trials = repmat(emptyTrial(), 0, 1);
conditions = repmat(emptyCondition(), 0, 1);
trialId = uint64(0);
conditionId = uint64(0);

for offsetSec = offsets
    relativeStart = floor(offsetSec * sampleRateHz);
    if relativeStart >= numel(iq)
        continue;
    end
    maxCount = min(numel(iq) - relativeStart, ...
        ceil(max(durations) * sampleRateHz));
    base = iq(relativeStart+1:relativeStart+maxCount);
    absoluteStart = uint64(p.Results.BaseSourceSample) + uint64(relativeStart);
    for snrDb = snrValues
        for randomSeed = randomSeeds
            rng(randomSeed, 'twister');
            noisy = addRelativeAwgn(base, snrDb);
            for frequencyOffsetHz = frequencyOffsets
                conditionId = conditionId + uint64(1);
                shifted = addFrequencyOffset(noisy, sampleRateHz, frequencyOffsetHz);
                conditionTrials = repmat(emptyTrial(), 0, 1);
                for windowSec = durations
                    trialId = trialId + uint64(1);
                    wantedCount = ceil(windowSec * sampleRateHz);
                    if wantedCount > numel(shifted)
                        trial = makeUnavailableTrial(trialId, conditionId, protocol, ...
                            offsetSec, snrDb, frequencyOffsetHz, randomSeed, ...
                            windowSec, absoluteStart, numel(shifted));
                    else
                        snapshot = radio.stream.makeIqChunk( ...
                            shifted(1:wantedCount), sampleRateHz, absoluteStart);
                        result = runProbe(snapshot, probe, trialId, p.Results.ProbeFcn);
                        trial = makeTrial(trialId, conditionId, protocol, ...
                            offsetSec, snrDb, frequencyOffsetHz, randomSeed, ...
                            windowSec, sampleRateHz, result);
                    end
                    trials(end+1, 1) = trial; %#ok<AGROW>
                    conditionTrials(end+1, 1) = trial; %#ok<AGROW>
                    if p.Results.StopAfterFirstConfirmation && trial.confirmed
                        break;
                    end
                end
                conditions(end+1, 1) = summarizeCondition( ...
                    conditionId, protocol, offsetSec, snrDb, ...
                    frequencyOffsetHz, randomSeed, conditionTrials); %#ok<AGROW>
            end
        end
    end
end

report = struct();
report.protocol = protocol;
report.sampleRateHz = double(sampleRateHz);
report.settings = struct( ...
    'startOffsetsSec', offsets, ...
    'windowDurationsSec', durations, ...
    'snrDb', snrValues, ...
    'frequencyOffsetsHz', frequencyOffsets, ...
    'randomSeed', p.Results.RandomSeed, ...
    'randomSeeds', randomSeeds, ...
    'stopAfterFirstConfirmation', logical(p.Results.StopAfterFirstConfirmation));
report.trials = trials;
report.conditions = conditions;
report.summary = summarizeAcrossOffsets(conditions);
clear rngCleanup;
end

function durations = progressiveWindows(probe)
durations = probe.initialWindowSec;
while durations(end) < probe.maxWindowSec
    next = min(probe.maxWindowSec, ...
        durations(end) * probe.windowGrowthFactor);
    if next <= durations(end)
        break;
    end
    durations(end+1) = next; %#ok<AGROW>
end
end

function result = runProbe(snapshot, probe, trialId, customFcn)
if isempty(customFcn)
    state = radio.stream.probeStateInit( ...
        probe, trialId, uint64(1), snapshot.sourceSampleStart);
    [~, result] = radio.stream.runProtocolProbe(state, snapshot, probe);
else
    result = customFcn(snapshot, probe, trialId, uint64(1));
end
end

function y = addRelativeAwgn(x, snrDb)
if isinf(snrDb) && snrDb > 0
    y = x(:);
    return;
end
signalPower = mean(abs(double(x(:))).^2);
noisePower = signalPower / (10 ^ (snrDb / 10));
noise = sqrt(noisePower / 2) .* ...
    (randn(size(x(:))) + 1i .* randn(size(x(:))));
y = x(:) + noise;
end

function y = addFrequencyOffset(x, sampleRateHz, offsetHz)
n = (0:numel(x)-1).';
y = x(:) .* exp(1i .* 2 .* pi .* offsetHz .* n ./ sampleRateHz);
end

function trial = makeTrial(id, conditionId, protocol, offsetSec, snrDb, ...
        frequencyOffsetHz, randomSeed, requestedWindowSec, sampleRateHz, result)
trial = emptyTrial();
trial.trialId = id;
trial.conditionId = conditionId;
trial.protocol = protocol;
trial.startOffsetSec = offsetSec;
trial.snrDb = snrDb;
trial.frequencyOffsetHz = frequencyOffsetHz;
trial.randomSeed = randomSeed;
trial.requestedWindowSec = requestedWindowSec;
trial.actualWindowSec = double(result.consumedSamples) / sampleRateHz;
trial.status = result.status;
trial.confirmed = strcmp(result.status, 'confirmed');
trial.confidence = result.confidence;
trial.evidenceClass = result.evidenceClass;
trial.elapsedSec = result.elapsedSec;
trial.pduCount = result.pduCount;
trial.windowStartSample = result.windowStartSample;
trial.windowEndSample = result.windowEndSample;
trial.reason = result.reason;
end

function trial = makeUnavailableTrial(id, conditionId, protocol, offsetSec, ...
        snrDb, frequencyOffsetHz, randomSeed, requestedWindowSec, ...
        absoluteStart, availableCount)
trial = emptyTrial();
trial.trialId = id;
trial.conditionId = conditionId;
trial.protocol = protocol;
trial.startOffsetSec = offsetSec;
trial.snrDb = snrDb;
trial.frequencyOffsetHz = frequencyOffsetHz;
trial.randomSeed = randomSeed;
trial.requestedWindowSec = requestedWindowSec;
trial.actualWindowSec = NaN;
trial.status = 'unavailable';
trial.windowStartSample = absoluteStart;
trial.windowEndSample = absoluteStart + uint64(availableCount);
trial.reason = 'input_shorter_than_requested_window';
end

function condition = summarizeCondition(id, protocol, offsetSec, snrDb, ...
        frequencyOffsetHz, randomSeed, trials)
condition = emptyCondition();
condition.conditionId = id;
condition.protocol = protocol;
condition.startOffsetSec = offsetSec;
condition.snrDb = snrDb;
condition.frequencyOffsetHz = frequencyOffsetHz;
condition.randomSeed = randomSeed;
confirmed = trials([trials.confirmed]);
condition.confirmed = ~isempty(confirmed);
if ~isempty(confirmed)
    condition.minimumConfirmationSec = min([confirmed.requestedWindowSec]);
    condition.evidenceClass = confirmed(1).evidenceClass;
end
condition.attemptCount = numel(trials);
condition.elapsedSec = sum([trials.elapsedSec]);
end

function summaries = summarizeAcrossOffsets(conditions)
summaries = repmat(emptySummary(), 0, 1);
if isempty(conditions), return; end
snrValues = unique([conditions.snrDb]);
frequencyOffsets = unique([conditions.frequencyOffsetHz]);
for snrDb = snrValues
    for frequencyOffsetHz = frequencyOffsets
        mask = [conditions.snrDb] == snrDb & ...
            [conditions.frequencyOffsetHz] == frequencyOffsetHz;
        group = conditions(mask);
        confirmed = group([group.confirmed]);
        values = [confirmed.minimumConfirmationSec];
        summary = emptySummary();
        summary.snrDb = snrDb;
        summary.frequencyOffsetHz = frequencyOffsetHz;
        summary.conditionCount = numel(group);
        summary.confirmedCount = numel(confirmed);
        summary.successRatio = numel(confirmed) / max(1, numel(group));
        if ~isempty(values)
            summary.p50Sec = localPercentile(values, 50);
            summary.p95Sec = localPercentile(values, 95);
            summary.p99Sec = localPercentile(values, 99);
            summary.maxSec = max(values);
        end
        summaries(end+1, 1) = summary; %#ok<AGROW>
    end
end
end

function value = localPercentile(values, percentile)
values = sort(double(values(:)));
if numel(values) == 1
    value = values(1);
    return;
end
position = 1 + (numel(values) - 1) * percentile / 100;
lower = floor(position);
upper = ceil(position);
fraction = position - lower;
value = values(lower) * (1 - fraction) + values(upper) * fraction;
end

function trial = emptyTrial()
trial = struct( ...
    'trialId', uint64(0), ...
    'conditionId', uint64(0), ...
    'protocol', '', ...
    'startOffsetSec', 0, ...
    'snrDb', inf, ...
    'frequencyOffsetHz', 0, ...
    'randomSeed', 0, ...
    'requestedWindowSec', 0, ...
    'actualWindowSec', 0, ...
    'status', '', ...
    'confirmed', false, ...
    'confidence', 0, ...
    'evidenceClass', '', ...
    'elapsedSec', 0, ...
    'pduCount', 0, ...
    'windowStartSample', uint64(0), ...
    'windowEndSample', uint64(0), ...
    'reason', '');
end

function condition = emptyCondition()
condition = struct( ...
    'conditionId', uint64(0), ...
    'protocol', '', ...
    'startOffsetSec', 0, ...
    'snrDb', inf, ...
    'frequencyOffsetHz', 0, ...
    'randomSeed', 0, ...
    'confirmed', false, ...
    'minimumConfirmationSec', NaN, ...
    'evidenceClass', '', ...
    'attemptCount', 0, ...
    'elapsedSec', 0);
end

function summary = emptySummary()
summary = struct( ...
    'snrDb', inf, ...
    'frequencyOffsetHz', 0, ...
    'conditionCount', 0, ...
    'confirmedCount', 0, ...
    'successRatio', 0, ...
    'p50Sec', NaN, ...
    'p95Sec', NaN, ...
    'p99Sec', NaN, ...
    'maxSec', NaN);
end
