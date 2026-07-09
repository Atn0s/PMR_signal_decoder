function pdus = scanIq(iq, sampleRate, varargin)
%SCANIQ Run the MATLAB offline IQ orchestration path.
p = inputParser;
p.addParameter('FreqList', []);
p.addParameter('BlindSearch', false);
p.addParameter('ProtocolNames', {});
p.addParameter('RadioConfig', radio.defaultConfig());
p.addParameter('DecoderBackend', 'matlab');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.addParameter('Deduplicate', true);
p.parse(varargin{:});

if isempty(sampleRate)
    error('radio:scanIq:MissingSampleRate', 'sampleRate is required.');
end

enabled = radio.normalizeProtocolNames(p.Results.ProtocolNames);
cfg = p.Results.RadioConfig;
freqList = p.Results.FreqList;

pdus = struct([]);
if ~isempty(freqList)
    for k = 1:numel(freqList)
        next = radio.processCandidate(iq, freqList(k), sampleRate, enabled, ...
            'RadioConfig', cfg, ...
            'DecoderBackend', p.Results.DecoderBackend, ...
            'PythonRoot', p.Results.PythonRoot, ...
            'PythonExecutable', p.Results.PythonExecutable, ...
            'Deduplicate', p.Results.Deduplicate);
        pdus = appendStructArray(pdus, next);
    end
elseif p.Results.BlindSearch
    offsets = radio.psdBlindSearch(iq, sampleRate, cfg);
    for k = 1:numel(offsets)
        next = radio.processCandidate(iq, offsets(k), sampleRate, enabled, ...
            'RadioConfig', cfg, ...
            'DecoderBackend', p.Results.DecoderBackend, ...
            'PythonRoot', p.Results.PythonRoot, ...
            'PythonExecutable', p.Results.PythonExecutable, ...
            'Deduplicate', p.Results.Deduplicate);
        pdus = appendStructArray(pdus, next);
    end
else
    pdus = radio.processBaseband(iq, sampleRate, enabled, ...
        'RadioConfig', cfg, ...
        'DecoderBackend', p.Results.DecoderBackend, ...
        'PythonRoot', p.Results.PythonRoot, ...
        'PythonExecutable', p.Results.PythonExecutable, ...
        'Deduplicate', p.Results.Deduplicate);
end

pdus = radio.postprocessPdus(pdus, enabled);
if p.Results.Deduplicate
    pdus = radio.deduplicatePdus(pdus);
end
end

function out = appendStructArray(a, b)
if isempty(a)
    out = b;
elseif isempty(b)
    out = a;
else
    out = [a(:); b(:)].';
end
end
