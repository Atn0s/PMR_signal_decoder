function pdus = scanIqNarrowband(iq, sampleRate, enabledProtocols, varargin)
%SCANIQNARROWBAND Run the 48 kHz narrowband 4FSK candidate pipeline.
p = inputParser;
p.addParameter('FreqList', []);
p.addParameter('BlindSearch', false);
p.addParameter('RadioConfig', radio.defaultConfig());
p.addParameter('DecoderBackend', 'matlab');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.addParameter('Deduplicate', true);
p.addParameter('ShowProgress', false);
p.parse(varargin{:});

cfg = p.Results.RadioConfig;
freqList = p.Results.FreqList;

pdus = struct([]);
if ~isempty(freqList)
    for k = 1:numel(freqList)
        next = radio.processCandidate(iq, freqList(k), sampleRate, enabledProtocols, ...
            'RadioConfig', cfg, ...
            'DecoderBackend', p.Results.DecoderBackend, ...
            'PythonRoot', p.Results.PythonRoot, ...
            'PythonExecutable', p.Results.PythonExecutable, ...
            'Deduplicate', p.Results.Deduplicate);
        pdus = radio.appendPdus(pdus, next);
    end
elseif p.Results.BlindSearch
    offsets = radio.psdBlindSearch(iq, sampleRate, cfg);
    if p.Results.ShowProgress
        fprintf('[radio] Blind search found %d channel candidate(s).\n', numel(offsets));
    end
    for k = 1:numel(offsets)
        if p.Results.ShowProgress
            fprintf('[radio] Decoding candidate %d/%d at %+.1f Hz ...\n', ...
                k, numel(offsets), offsets(k));
        end
        next = radio.processCandidate(iq, offsets(k), sampleRate, enabledProtocols, ...
            'RadioConfig', cfg, ...
            'DecoderBackend', p.Results.DecoderBackend, ...
            'PythonRoot', p.Results.PythonRoot, ...
            'PythonExecutable', p.Results.PythonExecutable, ...
            'Deduplicate', p.Results.Deduplicate);
        pdus = radio.appendPdus(pdus, next);
        if p.Results.ShowProgress
            fprintf('[radio] Candidate %d/%d complete: %d PDU(s).\n', ...
                k, numel(offsets), numel(next));
        end
    end
else
    pdus = radio.processBaseband(iq, sampleRate, enabledProtocols, ...
        'RadioConfig', cfg, ...
        'DecoderBackend', p.Results.DecoderBackend, ...
        'PythonRoot', p.Results.PythonRoot, ...
        'PythonExecutable', p.Results.PythonExecutable, ...
        'Deduplicate', p.Results.Deduplicate);
end
end
