function spec = specForProtocol(name)
canonical = radio.normalizeProtocolNames({name});
specs = radio.protocolRegistry();
for k = 1:numel(specs)
    if strcmp(specs(k).name, canonical{1})
        spec = specs(k);
        return;
    end
end
error('radio:specForProtocol:Unsupported', 'Unsupported protocol: %s', char(name));
end

