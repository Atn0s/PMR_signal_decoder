function runTunedTransition()
%RUNTUNEDTRANSITION Deterministic known-carrier DDC transition tests.
testHeaderedRawExtraction();
testValidation();
fprintf('Known-carrier tuned-transition tests passed.\n');
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
