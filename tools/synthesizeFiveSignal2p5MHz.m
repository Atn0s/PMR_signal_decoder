function manifest = synthesizeFiveSignal2p5MHz(varargin)
%SYNTHESIZEFIVESIGNAL2P5MHZ Build a near-synchronous five-protocol IQ fixture.
%
% The generated capture contains one known-decodable excerpt for each of
% DMR, P25, dPMR, NXDN, and TETRA.  The excerpts are independently
% resampled, power-normalized, repeatedly tiled into five-second activity
% placements, placed on five well-separated carriers, and started 20 ms
% apart by default.  Output is headerless little-endian CI16.
%
% Example:
%   manifest = synthesizeFiveSignal2p5MHz( ...
%       'OutputPath', fullfile('signal_data', ...
%           'synthesized_5sync_2.5MHz.rawiq'), ...
%       'Overwrite', true);

p = inputParser;
p.addParameter('OutputPath', fullfile(projectRoot(), 'signal_data', ...
    'synthesized_5sync_2.5MHz.rawiq'));
p.addParameter('OutputSampleRateHz', 2.5e6);
p.addParameter('OnsetSec', 0.80);
p.addParameter('OnsetStaggerSec', 0.020);
p.addParameter('ActiveDurationSec', 5.0);
p.addParameter('TailSec', 0.60);
p.addParameter('PerSignalSnrDb', 25);
p.addParameter('TargetSignalRms', 0.12);
p.addParameter('FadeSec', 0.005);
p.addParameter('PeakFraction', 0.90);
p.addParameter('RandomSeed', 2505);
p.addParameter('PythonRoot', pybackend.defaultPythonRoot());
p.addParameter('NxdnRoot', fullfile(projectRoot(), 'signal_data'));
p.addParameter('Overwrite', false);
p.addParameter('WriteManifest', true);
p.addParameter('Verbose', true);
p.parse(varargin{:});
options = p.Results;

validateOptions(options);
outputPath = absolutePath(char(options.OutputPath));
manifestPath = [outputPath, '.json'];
ensureWritableTarget(outputPath, manifestPath, options);

specs = defaultSpecs(char(options.PythonRoot), char(options.NxdnRoot));
for k = 1:numel(specs)
    specs(k).channelId = k;
    specs(k).outputStartSec = options.OnsetSec + ...
        (k - 1) * options.OnsetStaggerSec;
    specs(k).outputDurationSec = options.ActiveDurationSec;
end
durationSec = max([specs.outputStartSec] + [specs.outputDurationSec]) + ...
    options.TailSec;
sampleRateHz = double(options.OutputSampleRateHz);
sampleCount = round(durationSec * sampleRateHz);
durationSec = sampleCount / sampleRateHz;
wideband = complex(zeros(sampleCount, 1));

savedRng = rng;
rngCleanup = onCleanup(@() rng(savedRng));
rng(double(options.RandomSeed), 'twister');

if options.Verbose
    fprintf('Synthesizing %.3f s at %.3f MS/s (%d complex samples).\n', ...
        durationSec, sampleRateHz / 1e6, sampleCount);
end

for k = 1:numel(specs)
    spec = specs(k);
    validateSource(spec);
    iq = common.readRawIq(spec.sourcePath);
    firstInput = floor(spec.sourceStartSec * spec.inputSampleRateHz) + 1;
    inputCount = round(spec.sourceDurationSec * spec.inputSampleRateHz);
    lastInput = firstInput + inputCount - 1;
    if lastInput > numel(iq)
        error('radio:testsignal:SourceTooShort', ...
            '%s needs samples [%d,%d], but only %d are available.', ...
            spec.sourcePath, firstInput, lastInput, numel(iq));
    end
    excerpt = iq(firstInput:lastInput);
    [pFactor, qFactor] = rat(sampleRateHz / spec.inputSampleRateHz, 1e-12);
    resampled = resample(excerpt, pFactor, qFactor);
    templateOutputCount = round(spec.sourceDurationSec * sampleRateHz);
    resampled = forceLength(resampled, templateOutputCount);
    sourceRms = sqrt(mean(abs(resampled).^2));
    if ~isfinite(sourceRms) || sourceRms <= 0
        error('radio:testsignal:EmptySource', ...
            'The selected %s excerpt has no usable IQ energy.', spec.protocol);
    end
    resampled = resampled .* (options.TargetSignalRms / sourceRms);
    outputCount = round(spec.outputDurationSec * sampleRateHz);
    resampled = repeatToLength(resampled, outputCount);
    resampled = applyEdgeFade(resampled, ...
        round(options.FadeSec * sampleRateHz));

    firstOutput = round(spec.outputStartSec * sampleRateHz) + 1;
    lastOutput = firstOutput + outputCount - 1;
    outputIndices = (firstOutput - 1:lastOutput - 1).';
    oscillator = exp(1i .* 2 .* pi .* spec.frequencyOffsetHz .* ...
        outputIndices ./ sampleRateHz);
    wideband(firstOutput:lastOutput) = wideband(firstOutput:lastOutput) + ...
        resampled .* oscillator;

    specs(k).inputSampleStart = uint64(firstInput - 1);
    specs(k).inputSampleCount = uint64(inputCount);
    specs(k).outputSampleStart = uint64(firstOutput - 1);
    specs(k).outputSampleCount = uint64(outputCount);
    specs(k).outputEndSec = lastOutput / sampleRateHz;
    specs(k).resampleNumerator = pFactor;
    specs(k).resampleDenominator = qFactor;
    specs(k).sourceExcerptRms = sourceRms;
    if options.Verbose
        fprintf(['  ch%d %-5s %+.0f kHz: source %.3f..%.3f s, ', ...
            'output %.3f..%.3f s\n'], ...
            k, spec.protocol, spec.frequencyOffsetHz / 1e3, ...
            spec.sourceStartSec, ...
            spec.sourceStartSec + spec.sourceDurationSec, ...
            spec.outputStartSec, specs(k).outputEndSec);
    end
end

noiseRms = options.TargetSignalRms * ...
    10 ^ (-double(options.PerSignalSnrDb) / 20);
noise = noiseRms / sqrt(2) .* ...
    (randn(sampleCount, 1) + 1i .* randn(sampleCount, 1));
wideband = wideband + noise;
unscaledPeak = max(abs(wideband));
if ~isfinite(unscaledPeak) || unscaledPeak <= 0
    error('radio:testsignal:EmptyOutput', 'Synthesized IQ is empty.');
end
scaleApplied = double(options.PeakFraction) / unscaledPeak;
wideband = wideband .* scaleApplied;

outputDir = fileparts(outputPath);
if exist(outputDir, 'dir') ~= 7
    mkdir(outputDir);
end
writeCi16(outputPath, wideband);

manifest = struct( ...
    'schemaVersion', 1, ...
    'description', ['Near-synchronous DMR/P25/dPMR/NXDN/TETRA ', ...
        'five-carrier MATLAB acceptance fixture'], ...
    'outputPath', outputPath, ...
    'format', 'ci16_le_interleaved_iq', ...
    'sampleRateHz', sampleRateHz, ...
    'centerFrequencyHz', 0, ...
    'sampleCount', uint64(sampleCount), ...
    'durationSec', durationSec, ...
    'onsetSec', double(options.OnsetSec), ...
    'onsetStaggerSec', double(options.OnsetStaggerSec), ...
    'activeDurationSec', double(options.ActiveDurationSec), ...
    'perSignalSnrDb', double(options.PerSignalSnrDb), ...
    'noiseRmsBeforeOutputScaling', noiseRms, ...
    'unscaledPeak', unscaledPeak, ...
    'scaleApplied', scaleApplied, ...
    'peakFraction', double(options.PeakFraction), ...
    'randomSeed', double(options.RandomSeed), ...
    'channels', specs);

if options.WriteManifest
    writeJson(manifestPath, manifest);
end
if options.Verbose
    fileInfo = dir(outputPath);
    fprintf('Wrote %s (%.1f MiB).\n', outputPath, ...
        double(fileInfo.bytes) / 2^20);
    if options.WriteManifest
        fprintf('Wrote %s.\n', manifestPath);
    end
end
clear rngCleanup;
end

function specs = defaultSpecs(pythonRoot, nxdnRoot)
dataRoot = fullfile(pythonRoot, 'data');
specs = [ ...
    makeSpec('DMR', -800e3, fullfile(dataRoot, ...
        'dmr_1_78125.rawiq'), 78125, 1.5, 1.5), ...
    makeSpec('P25', -400e3, fullfile(dataRoot, ...
        'p25_1_78125.rawiq'), 78125, 6.0, 1.5), ...
    makeSpec('dPMR', 0, fullfile(dataRoot, ...
        'dpmr_1_48000.rawiq'), 48000, 0.2, 1.5), ...
    makeSpec('NXDN', 400e3, fullfile(nxdnRoot, ...
        'nxdn96_1_78125.rawiq'), 78125, 1.0, 1.0), ...
    makeSpec('TETRA', 800e3, fullfile(dataRoot, ...
        'tetra_dmo_20240413_430050000_baseband.wav'), 50000, 5.15, 1.0)];
end

function spec = makeSpec(protocol, offsetHz, path, inputFs, startSec, durationSec)
spec = struct( ...
    'channelId', 0, ...
    'protocol', protocol, ...
    'frequencyOffsetHz', double(offsetHz), ...
    'sourcePath', char(path), ...
    'inputSampleRateHz', double(inputFs), ...
    'sourceStartSec', double(startSec), ...
    'sourceDurationSec', double(durationSec), ...
    'outputStartSec', 0, ...
    'outputDurationSec', 0, ...
    'outputEndSec', 0, ...
    'inputSampleStart', uint64(0), ...
    'inputSampleCount', uint64(0), ...
    'outputSampleStart', uint64(0), ...
    'outputSampleCount', uint64(0), ...
    'resampleNumerator', 0, ...
    'resampleDenominator', 0, ...
    'sourceExcerptRms', 0);
end

function validateOptions(options)
validateattributes(options.OutputSampleRateHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
if options.OutputSampleRateHz ~= 2.5e6
    error('radio:testsignal:OutputSampleRate', ...
        'This fixture is intentionally fixed at 2.5 MS/s.');
end
validateattributes(options.OnsetSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(options.OnsetStaggerSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(options.ActiveDurationSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
validateattributes(options.TailSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(options.PerSignalSnrDb, {'numeric'}, ...
    {'scalar', 'real', 'finite'});
validateattributes(options.TargetSignalRms, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
validateattributes(options.FadeSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(options.PeakFraction, {'numeric'}, ...
    {'scalar', 'real', 'finite', '>', 0, '<=', 1});
validateattributes(options.RandomSeed, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'nonnegative'});
end

function validateSource(spec)
if exist(spec.sourcePath, 'file') ~= 2
    error('radio:testsignal:MissingSource', ...
        'Missing %s source: %s', spec.protocol, spec.sourcePath);
end
detectedFs = common.detectSampleRate(spec.sourcePath);
if ~isempty(detectedFs) && detectedFs ~= spec.inputSampleRateHz
    error('radio:testsignal:SourceSampleRate', ...
        '%s source reports %g Hz; the fixture expects %g Hz.', ...
        spec.protocol, detectedFs, spec.inputSampleRateHz);
end
end

function values = forceLength(values, count)
values = values(:);
if numel(values) > count
    values = values(1:count);
elseif numel(values) < count
    values(end+1:count, 1) = 0;
end
end

function values = repeatToLength(template, count)
if isempty(template)
    values = complex(zeros(count, 1));
    return;
end
repeatCount = ceil(count / numel(template));
values = repmat(template, repeatCount, 1);
values = values(1:count);
end

function values = applyEdgeFade(values, fadeSamples)
fadeSamples = min(floor(numel(values) / 2), max(0, fadeSamples));
if fadeSamples == 0
    return;
end
phase = (1:fadeSamples).' ./ (fadeSamples + 1);
ramp = sin(0.5 .* pi .* phase) .^ 2;
values(1:fadeSamples) = values(1:fadeSamples) .* ramp;
values(end-fadeSamples+1:end) = values(end-fadeSamples+1:end) .* ...
    flipud(ramp);
end

function writeCi16(path, iq)
fid = fopen(path, 'wb', 'ieee-le');
if fid < 0
    error('radio:testsignal:OpenOutput', ...
        'Unable to create IQ output: %s', path);
end
cleanup = onCleanup(@() fclose(fid));
blockSamples = 1e6;
for first = 1:blockSamples:numel(iq)
    last = min(numel(iq), first + blockSamples - 1);
    block = iq(first:last);
    raw = zeros(2 * numel(block), 1, 'int16');
    raw(1:2:end) = toInt16(real(block));
    raw(2:2:end) = toInt16(imag(block));
    count = fwrite(fid, raw, 'int16');
    if count ~= numel(raw)
        error('radio:testsignal:ShortWrite', ...
            'Incomplete write while creating %s.', path);
    end
end
clear cleanup;
end

function values = toInt16(values)
values = round(32767 .* values);
values = min(32767, max(-32768, values));
values = int16(values);
end

function writeJson(path, value)
try
    payload = jsonencode(value, 'PrettyPrint', true);
catch
    payload = jsonencode(value);
end
fid = fopen(path, 'w');
if fid < 0
    error('radio:testsignal:OpenManifest', ...
        'Unable to create manifest: %s', path);
end
cleanup = onCleanup(@() fclose(fid));
count = fwrite(fid, payload, 'char');
if count ~= numel(payload)
    error('radio:testsignal:ShortManifestWrite', ...
        'Incomplete manifest write: %s', path);
end
fwrite(fid, newline, 'char');
clear cleanup;
end

function ensureWritableTarget(outputPath, manifestPath, options)
if exist(outputPath, 'file') == 2 && ~options.Overwrite
    error('radio:testsignal:OutputExists', ...
        'Output already exists; pass Overwrite=true: %s', outputPath);
end
if options.WriteManifest && exist(manifestPath, 'file') == 2 && ...
        ~options.Overwrite
    error('radio:testsignal:ManifestExists', ...
        'Manifest already exists; pass Overwrite=true: %s', manifestPath);
end
end

function path = absolutePath(path)
if isempty(path)
    error('radio:testsignal:OutputPath', 'OutputPath cannot be empty.');
end
if ~isAbsolute(path)
    path = fullfile(pwd, path);
end
end

function tf = isAbsolute(path)
if ispc
    tf = ~isempty(regexp(path, '^[A-Za-z]:[\\/]|^\\\\', 'once'));
else
    tf = startsWith(path, filesep);
end
end

function root = projectRoot()
root = fileparts(fileparts(mfilename('fullpath')));
end
