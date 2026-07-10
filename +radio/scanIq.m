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

protocolNames = p.Results.ProtocolNames;
[enabled, explicitProtocols] = radio.resolveScanProtocols(protocolNames, ...
    'FreqList', p.Results.FreqList, ...
    'BlindSearch', p.Results.BlindSearch);
cfg = p.Results.RadioConfig;

narrowEnabled = protocolsByMode(enabled, 'narrowband_4fsk');
windowEnabled = protocolsByMode(enabled, 'windowed_iq');

if p.Results.BlindSearch && isempty(p.Results.FreqList) && ~isempty(windowEnabled)
    if explicitProtocols
        error('radio:scanIq:TetraBlindSearchUnsupported', ...
            ['TETRA wideband blind search is not supported yet; pass FreqList ', ...
             'or provide centered TETRA baseband with BlindSearch=false.']);
    end
    windowEnabled = {};
end

pdus = struct([]);
if ~isempty(narrowEnabled)
    next = radio.scanIqNarrowband(iq, sampleRate, narrowEnabled, ...
        'FreqList', p.Results.FreqList, ...
        'BlindSearch', p.Results.BlindSearch, ...
        'RadioConfig', cfg, ...
        'DecoderBackend', p.Results.DecoderBackend, ...
        'PythonRoot', p.Results.PythonRoot, ...
        'PythonExecutable', p.Results.PythonExecutable, ...
        'Deduplicate', p.Results.Deduplicate);
    pdus = radio.appendPdus(pdus, next);
end
if ~isempty(windowEnabled)
    next = scanWindowedIq(iq, sampleRate, windowEnabled, p.Results.FreqList);
    pdus = radio.appendPdus(pdus, next);
end

pdus = radio.postprocessPdus(pdus, enabled);
if p.Results.Deduplicate
    pdus = radio.deduplicatePdus(pdus);
end
end

function names = protocolsByMode(enabled, mode)
specs = radio.protocolRegistry();
names = {};
for k = 1:numel(specs)
    if any(strcmp(enabled, specs(k).name)) && strcmp(specs(k).scanMode, mode)
        names{end + 1} = specs(k).name; %#ok<AGROW>
    end
end
end

function pdus = scanWindowedIq(iq, sampleRate, enabledProtocols, freqList)
specs = radio.protocolRegistry();
pdus = struct([]);
for k = 1:numel(specs)
    spec = specs(k);
    if ~any(strcmp(enabledProtocols, spec.name))
        continue;
    end
    if isempty(spec.scanIqFcn)
        error('radio:scanIq:MissingWindowScanner', ...
            'Protocol %s does not provide a windowed-IQ scanner.', spec.name);
    end
    if isempty(freqList)
        next = runWindowedSpec(spec, iq, sampleRate, []);
        pdus = radio.appendPdus(pdus, next);
    else
        for n = 1:numel(freqList)
            shifted = shiftIq(iq, sampleRate, freqList(n));
            next = runWindowedSpec(spec, shifted, sampleRate, freqList(n));
            pdus = radio.appendPdus(pdus, next);
        end
    end
end
end

function pdus = runWindowedSpec(spec, iq, sampleRate, foHz)
result = spec.scanIqFcn(iq, sampleRate, ...
    'ShowProgress', false, ...
    'WriteOutputs', false);
if isstruct(result) && isfield(result, 'pdus')
    pdus = result.pdus;
else
    pdus = result;
end
pdus = radio.normalizePdus(pdus);
if ~isempty(foHz)
    pdus = radio.addMeta(pdus, '_fo_hz', foHz);
end
end

function shifted = shiftIq(iq, sampleRate, foHz)
t = (0:numel(iq)-1).' ./ sampleRate;
shifted = iq(:) .* exp(-1i * 2 * pi * foHz .* t);
end
