function [pdus, report] = scanBasebandFile(path, varargin)
%SCANBASEBANDFILE Identify and decode all RF Epochs in one baseband file.
p = inputParser;
p.addParameter('ProtocolNames', {});
p.addParameter('SampleRate', []);
p.addParameter('IqDType', 'int16');
p.addParameter('StreamConfig', radio.stream.defaultConfig());
p.addParameter('RadioConfig', radio.defaultConfig());
p.addParameter('Mode', 'parallel');
p.addParameter('NumWorkers', 5);
p.addParameter('PoolType', 'processes');
p.addParameter('TimeoutSec', 120);
p.addParameter('DecoderBackend', 'matlab');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.addParameter('Deduplicate', true);
p.addParameter('ShowProgress', false);
p.parse(varargin{:});

if exist(path, 'file') ~= 2
    error('radio:stream:scanBasebandFile:NotFound', ...
        'IQ input file does not exist: %s', char(path));
end
sampleRateHz = p.Results.SampleRate;
if isempty(sampleRateHz)
    sampleRateHz = common.detectSampleRate(path);
end
if isempty(sampleRateHz)
    error('radio:stream:scanBasebandFile:MissingSampleRate', ...
        'Sample rate is required; pass SampleRate or use filename metadata.');
end

iq = common.readRawIq(path, 'DType', p.Results.IqDType);
[pdus, report] = radio.stream.scanBasebandIqEpochs(iq, sampleRateHz, ...
    'ProtocolNames', p.Results.ProtocolNames, ...
    'Config', p.Results.StreamConfig, ...
    'RadioConfig', p.Results.RadioConfig, ...
    'Mode', p.Results.Mode, ...
    'NumWorkers', p.Results.NumWorkers, ...
    'PoolType', p.Results.PoolType, ...
    'TimeoutSec', p.Results.TimeoutSec, ...
    'DecoderBackend', p.Results.DecoderBackend, ...
    'PythonRoot', p.Results.PythonRoot, ...
    'PythonExecutable', p.Results.PythonExecutable, ...
    'Deduplicate', p.Results.Deduplicate, ...
    'ShowProgress', p.Results.ShowProgress);
report.path = char(path);
end
