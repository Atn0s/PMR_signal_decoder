function pdus = decodeIqEnabled(iqDec, enabledProtocols, sampleRate)
%DECODEIQENABLED Run native frontends and protocol decoders by registry spec.
specs = radio.protocolRegistry();
frontends = struct();
pdus = struct([]);

for k = 1:numel(specs)
    spec = specs(k);
    if ~any(strcmp(enabledProtocols, spec.name))
        continue;
    end
    key = matlab.lang.makeValidName(spec.frontendKey);
    if ~isfield(frontends, key)
        frontends.(key) = spec.frontendFcn(iqDec, sampleRate, spec.config);
    end
    next = spec.decodeFcn(frontends.(key), spec.config);
    next = radio.normalizePdus(next);
    pdus = appendStructArray(pdus, next);
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

