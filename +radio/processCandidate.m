function pdus = processCandidate(iq, fo, sourceSampleRate, enabledProtocols, varargin)
%PROCESSCANDIDATE DDC, resample, and decode one candidate offset.
p = inputParser;
p.addParameter('RadioConfig', radio.defaultConfig());
p.addParameter('DecoderBackend', 'matlab');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.addParameter('Deduplicate', true);
p.parse(varargin{:});
cfg = p.Results.RadioConfig;

t = (0:numel(iq)-1).' ./ sourceSampleRate;
iqShifted = iq(:) .* exp(-1i * 2 * pi * fo .* t);
targetFs = cfg.targetSampleRateHz;
if abs(sourceSampleRate - targetFs) < cfg.sampleRateToleranceHz
    iqDec = iqShifted;
else
    iqDec = common.resampleTo(iqShifted, sourceSampleRate, targetFs);
end

pdus = radio.decodeNarrowband(iqDec, enabledProtocols, targetFs, ...
    'DecoderBackend', p.Results.DecoderBackend, ...
    'PythonRoot', p.Results.PythonRoot, ...
    'PythonExecutable', p.Results.PythonExecutable, ...
    'Deduplicate', p.Results.Deduplicate);
pdus = radio.addMeta(pdus, '_fo_hz', fo);
end
