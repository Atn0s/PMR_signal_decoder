function [pdus, report] = scanBasebandFile(path, varargin)
%SCANBASEBANDFILE Parallel-identify and fully decode one offline baseband file.
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
totalTimer = tic;
identification = radio.stream.identifyBasebandIq(iq, sampleRateHz, ...
    'ProtocolNames', p.Results.ProtocolNames, ...
    'Config', p.Results.StreamConfig, ...
    'Mode', p.Results.Mode, ...
    'NumWorkers', p.Results.NumWorkers, ...
    'PoolType', p.Results.PoolType, ...
    'TimeoutSec', p.Results.TimeoutSec, ...
    'ShowProgress', p.Results.ShowProgress);

pdus = struct([]);
decodeElapsedSec = 0;
if strcmp(identification.outcome, 'confirmed')
    if p.Results.ShowProgress
        fprintf('[radio.parallel] confirmed %s; decoding complete file.\n', ...
            identification.selectedProtocol);
    end
    decodeTimer = tic;
    pdus = radio.scanIq(iq, sampleRateHz, ...
        'ProtocolNames', {identification.selectedProtocol}, ...
        'FreqList', [], ...
        'BlindSearch', false, ...
        'RadioConfig', p.Results.RadioConfig, ...
        'DecoderBackend', p.Results.DecoderBackend, ...
        'PythonRoot', p.Results.PythonRoot, ...
        'PythonExecutable', p.Results.PythonExecutable, ...
        'Deduplicate', p.Results.Deduplicate, ...
        'ShowProgress', p.Results.ShowProgress);
    decodeElapsedSec = toc(decodeTimer);
end
pdus = radio.normalizePdus(pdus);

report = identification;
report.path = char(path);
report.decodeElapsedSec = decodeElapsedSec;
report.totalElapsedSec = toc(totalTimer);
report.pduCount = numel(pdus);
end
