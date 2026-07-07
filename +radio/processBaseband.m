function pdus = processBaseband(iq, sourceSampleRate, enabledProtocols, varargin)
%PROCESSBASEBAND Resample a centered IQ stream and decode it.
p = inputParser;
p.addParameter('RadioConfig', radio.defaultConfig());
p.addParameter('DecoderBackend', 'matlab');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.parse(varargin{:});
cfg = p.Results.RadioConfig;

targetFs = cfg.targetSampleRateHz;
if abs(sourceSampleRate - targetFs) < cfg.sampleRateToleranceHz
    iqDec = iq(:);
else
    iqDec = common.resampleTo(iq(:), sourceSampleRate, targetFs);
end

pdus = radio.decodeNarrowband(iqDec, enabledProtocols, targetFs, ...
    'DecoderBackend', p.Results.DecoderBackend, ...
    'PythonRoot', p.Results.PythonRoot, ...
    'PythonExecutable', p.Results.PythonExecutable);
end
