function names = supportedProtocols()
specs = radio.protocolRegistry();
names = cell(1, numel(specs));
for k = 1:numel(specs)
    names{k} = specs(k).name;
end
end

