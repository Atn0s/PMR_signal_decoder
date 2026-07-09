function result = analyzeFile(path, varargin)
%ANALYZEFILE Decode an IQ file and show MATLAB-native diagnostic plots.
p = inputParser;
p.addParameter('ProtocolNames', {});
p.addParameter('SampleRate', []);
p.addParameter('IqDType', 'int16');
p.addParameter('FreqList', []);
p.addParameter('BlindSearch', false);
p.addParameter('PipelineBackend', 'matlab');
p.addParameter('DecoderBackend', 'matlab');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.addParameter('CreateFigure', true);
p.parse(varargin{:});

iq = common.readRawIq(path, 'DType', p.Results.IqDType);
fs = p.Results.SampleRate;
if isempty(fs)
    fs = common.detectSampleRate(path);
end
if isempty(fs)
    error('viz:analyzeFile:MissingSampleRate', ...
        'Sample rate is required; pass SampleRate or use filename metadata.');
end

cfg = radio.defaultConfig();
[previewIq, previewFs, previewFo, candidates] = preparePreviewIq( ...
    iq, fs, p.Results.FreqList, p.Results.BlindSearch, cfg);

enabled = radio.normalizeProtocolNames(p.Results.ProtocolNames);
frontProtocol = enabled{1};
frontendError = '';
try
    y = runFrontend(frontProtocol, previewIq, previewFs);
catch err
    y = zeros(0, 1);
    frontendError = err.message;
end

pdus = radio.scanFile(path, ...
    'ProtocolNames', p.Results.ProtocolNames, ...
    'SampleRate', p.Results.SampleRate, ...
    'IqDType', p.Results.IqDType, ...
    'FreqList', p.Results.FreqList, ...
    'BlindSearch', p.Results.BlindSearch, ...
    'PipelineBackend', p.Results.PipelineBackend, ...
    'DecoderBackend', p.Results.DecoderBackend, ...
    'PythonRoot', p.Results.PythonRoot, ...
    'PythonExecutable', p.Results.PythonExecutable);

result = struct();
result.path = char(path);
result.sampleRate = fs;
result.previewSampleRate = previewFs;
result.previewFoHz = previewFo;
result.candidatesHz = candidates;
result.protocols = enabled;
result.frontend = y;
result.frontendError = frontendError;
result.pdus = pdus;
result.lines = radio.formatLines(pdus);
result.table = radio.pduTable(pdus);

if p.Results.CreateFigure
    result.figure = viz.plotOverview(iq, fs, previewIq, previewFs, y, result);
end
end

function [previewIq, previewFs, previewFo, candidates] = preparePreviewIq(iq, fs, freqList, blindSearch, cfg)
previewFo = 0.0;
candidates = [];
if ~isempty(freqList)
    previewFo = freqList(1);
    candidates = freqList(:).';
elseif blindSearch
    candidates = radio.psdBlindSearch(iq, fs, cfg);
    if ~isempty(candidates)
        previewFo = candidates(1);
    end
end

t = (0:numel(iq)-1).' ./ fs;
shifted = iq(:) .* exp(-1i * 2 * pi * previewFo .* t);
if abs(fs - cfg.targetSampleRateHz) < cfg.sampleRateToleranceHz
    previewIq = shifted;
else
    previewIq = common.resampleTo(shifted, fs, cfg.targetSampleRateHz);
end
previewFs = cfg.targetSampleRateHz;
end

function y = runFrontend(protocol, iq, fs)
switch lower(char(protocol))
    case 'tetra'
        y = abs(iq(:));
    case 'dpmr'
        y = dpmr.frontend(iq, fs, dpmr.config());
    case 'p25'
        y = p25.frontend(iq, fs, p25.config());
    otherwise
        y = dmr.frontend(iq, fs, dmr.config());
end
end
