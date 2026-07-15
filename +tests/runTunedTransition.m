function runTunedTransition()
%RUNTUNEDTRANSITION Deterministic known-carrier DDC transition tests.
testHeaderedRawExtraction();
testValidation();
testRuntimeRateResolution();
testReusableExternalMixer();
fprintf('Known-carrier tuned-transition tests passed.\n');
end

function testReusableExternalMixer()
fs = 240000;
offsetHz = 40000;
cfg = radio.tuned.defaultConfig();
ddc = radio.tuned.ddcInit(fs, 0, 'Config', cfg, ...
    'MixerMode', 'external');
ddc.converter(complex(zeros(ddc.inputBlockSamples, 1)));
reset(ddc.converter);
ddc = radio.tuned.ddcRetarget(ddc, offsetHz, ...
    'InputCenterFrequencyHz', 10e6, 'ChannelId', 3);
n = (0:round(0.1 * fs)-1).';
iq = 0.3 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ fs);
chunk = radio.stream.makeIqChunk(iq, fs, uint64(50000), ...
    'CenterFrequencyHz', 10e6);
[ddc, output] = radio.tuned.ddcFeed(ddc, chunk);
assert(strcmp(ddc.mixerMode, 'external'));
assert(output.channelId == 3);
assert(output.centerFrequencyHz == 10e6 + offsetHz);
steady = output.iq(2401:4800);
carrier = mean(steady);
assert(abs(carrier) > 0.20);
assert(rms(steady - carrier) < 0.01);
end

function testRuntimeRateResolution()
cfg = radio.tuned.defaultConfig();
[resolved, report] = radio.tuned.resolveInputConfig(61.44e6, cfg);
assert(~report.adapted && resolved.outputSampleRateHz == 120000);
[resolved, report] = radio.tuned.resolveInputConfig(2.5e6, cfg);
assert(report.adapted && resolved.outputSampleRateHz == 125000);
assert(report.decimationFactor == 20);
end

function testHeaderedRawExtraction()
fs = 240000;
durationSamples = 10920; % Deliberately not a complete 10 ms DDC block.
inputCenterHz = 10e6;
offsetHz = 40000;
n = (0:durationSamples-1).';
target = 0.25 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ fs);
outOfChannel = 0.25 .* exp(1i .* 2 .* pi .* 110000 .* n ./ fs);
iq = target + outOfChannel;

path = [tempname, '_240000.rawiq'];
cleanup = onCleanup(@() deleteIfPresent(path));
fid = fopen(path, 'wb', 'ieee-le');
assert(fid >= 0);
assert(fwrite(fid, uint8(1:8), 'uint8') == 8);
raw = int16(round(32767 .* [real(iq).'; imag(iq).']));
assert(fwrite(fid, raw(:), 'int16') == 2 * durationSamples);
fclose(fid);

cfg = radio.tuned.defaultConfig();
cfg.filterFlushSec = 0;
[baseband, report] = radio.tuned.extractFile( ...
    path, inputCenterHz + offsetHz, ...
    'SampleRate', fs, ...
    'CenterFrequencyHz', inputCenterHz, ...
    'HeaderBytes', 8, ...
    'Config', cfg);
assert(report.headerBytes == 8);
assert(report.decimationFactor == 2);
assert(report.inputSampleCount == uint64(durationSamples));
assert(report.outputSampleRateHz == 120000);
assert(numel(baseband) == 6000);

steady = baseband(2401:4800);
carrier = mean(steady);
residual = steady - carrier;
assert(abs(carrier) > 0.20);
assert(rms(residual) < 0.05);
clear cleanup;
end

function testValidation()
cfg = radio.tuned.defaultConfig();
assertThrows(@() radio.tuned.ddcInit(250000, 0, 'Config', cfg), ...
    'radio:tuned:validateConfig:DecimationFactor');
assertThrows(@() radio.tuned.ddcInit(240000, 70000, 'Config', cfg), ...
    'radio:tuned:ddcInit:FrequencyOutsideInput');
end

function assertThrows(fn, identifier)
didThrow = false;
try
    fn();
catch ME
    didThrow = strcmp(ME.identifier, identifier);
end
assert(didThrow);
end

function deleteIfPresent(path)
if exist(path, 'file') == 2
    delete(path);
end
end
