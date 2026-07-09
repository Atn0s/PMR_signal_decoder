function pdus = decodeNarrowband(iqDec, enabledProtocols, sampleRate, varargin)
%DECODENARROWBAND Decode a 48 kHz narrowband candidate.
p = inputParser;
p.addParameter('DecoderBackend', 'matlab');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.addParameter('Deduplicate', true);
p.parse(varargin{:});

backend = lower(char(p.Results.DecoderBackend));
switch backend
    case {'python', 'compat', 'py'}
        pdus = pybackend.scanIq(iqDec, ...
            'SampleRate', sampleRate, ...
            'ProtocolNames', enabledProtocols, ...
            'PythonRoot', p.Results.PythonRoot, ...
            'PythonExecutable', p.Results.PythonExecutable, ...
            'Deduplicate', p.Results.Deduplicate);
    case {'matlab', 'native'}
        pdus = radio.decodeIqEnabled(iqDec, enabledProtocols, sampleRate);
    otherwise
        error('radio:decodeNarrowband:UnsupportedBackend', ...
            'Unsupported decoder backend: %s', backend);
end
pdus = radio.normalizePdus(pdus);
end
