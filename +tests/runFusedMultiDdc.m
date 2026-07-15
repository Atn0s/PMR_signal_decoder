function report = runFusedMultiDdc()
%RUNFUSEDMULTIDDC Verify matrix DDC equivalence and measure warm throughput.
fs = 2.5e6;
offsets = [-800e3; -400e3; 0; 400e3; 800e3];
[cfg, ~] = radio.tuned.resolveInputConfig(fs, radio.tuned.defaultConfig());
separate = cell(numel(offsets), 1);
for k = 1:numel(offsets)
    separate{k} = radio.tuned.ddcInit(fs, offsets(k), ...
        'Config', cfg, 'ChannelId', k, 'MixerMode', 'external');
    converter = separate{k}.converter;
    converter(complex(zeros(separate{k}.inputBlockSamples, 1)));
    reset(converter);
    separate{k}.converter = converter;
end
fused = radio.tuned.multiDdcInit(fs, offsets, ...
    'Config', cfg, 'Prewarm', true);

chunkSamples = round(cfg.chunkDurationSec * fs);
chunks = makeChunks(fs, chunkSamples, offsets, 24);
maxError = 0;
separateElapsed = 0;
fusedElapsed = 0;
for n = 1:numel(chunks)
    outputs = cell(numel(offsets), 1);
    token = tic;
    for k = 1:numel(offsets)
        [separate{k}, outputs{k}] = ...
            radio.tuned.ddcFeed(separate{k}, chunks{n});
    end
    separateElapsed = separateElapsed + toc(token);

    token = tic;
    [fused, fusedOutputs] = radio.tuned.multiDdcFeed(fused, chunks{n});
    fusedElapsed = fusedElapsed + toc(token);
    for k = 1:numel(offsets)
        assert(~isempty(outputs{k}) && ~isempty(fusedOutputs{k}));
        errorValue = max(abs(double(outputs{k}.iq) - ...
            double(fusedOutputs{k}.iq)));
        maxError = max(maxError, errorValue);
    end
end
assert(maxError < 1e-10, ...
    'Matrix DDC differs from independent external-mixer paths.');
speedup = separateElapsed / fusedElapsed;
report = struct( ...
    'chunkCount', numel(chunks), ...
    'maxAbsoluteError', maxError, ...
    'separateElapsedSec', separateElapsed, ...
    'fusedElapsedSec', fusedElapsed, ...
    'speedup', speedup, ...
    'fusedMeanBlockMs', 1e3 * fusedElapsed / numel(chunks), ...
    'separateMeanBlockMs', 1e3 * separateElapsed / numel(chunks));
assert(speedup > 1.0, ...
    'The matrix DDC did not improve warm five-channel throughput.');
fprintf(['Fused five-channel DDC: separate %.3f ms/block, ', ...
    'fused %.3f ms/block, speedup %.2fx, max error %.3g.\n'], ...
    report.separateMeanBlockMs, report.fusedMeanBlockMs, ...
    speedup, maxError);
end

function chunks = makeChunks(fs, chunkSamples, offsets, count)
saved = rng;
rng(5501);
chunks = cell(count, 1);
phaseBase = 0;
for k = 1:count
    n = (0:chunkSamples-1).' + phaseBase;
    iq = 0.005 .* (randn(chunkSamples, 1) + ...
        1i .* randn(chunkSamples, 1));
    for m = 1:numel(offsets)
        iq = iq + (0.03 + 0.005 * m) .* ...
            exp(1i .* 2 .* pi .* offsets(m) .* n ./ fs);
    end
    chunks{k} = radio.stream.makeIqChunk(iq, fs, ...
        uint64(phaseBase), 'SequenceNumber', uint64(k - 1));
    phaseBase = phaseBase + chunkSamples;
end
rng(saved);
end
