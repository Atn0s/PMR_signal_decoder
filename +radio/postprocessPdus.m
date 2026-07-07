function pdus = postprocessPdus(pdus, enabledProtocols)
%POSTPROCESSPDUS Run protocol postprocessors.
pdus = radio.normalizePdus(pdus);
if isempty(pdus)
    return;
end
specs = radio.protocolRegistry();
for k = 1:numel(specs)
    if any(strcmp(enabledProtocols, specs(k).name))
        pdus = specs(k).postprocessFcn(pdus);
    end
end
end

