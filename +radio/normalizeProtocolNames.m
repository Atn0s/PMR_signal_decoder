function names = normalizeProtocolNames(protocolNames)
%NORMALIZEPROTOCOLNAMES Canonicalize protocol names and aliases.
specs = radio.protocolRegistry();
if nargin < 1 || isempty(protocolNames)
    names = radio.supportedProtocols();
    return;
end

if ischar(protocolNames) || (isstring(protocolNames) && isscalar(protocolNames))
    protocolNames = cellstr(protocolNames);
elseif isstring(protocolNames)
    protocolNames = cellstr(protocolNames(:));
end

names = {};
for idx = 1:numel(protocolNames)
    key = lower(char(protocolNames{idx}));
    matched = '';
    for k = 1:numel(specs)
        aliases = [{lower(specs(k).name)}, specs(k).aliases];
        if any(strcmp(key, lower(string(aliases))))
            matched = specs(k).name;
            break;
        end
    end
    if isempty(matched)
        error('radio:normalizeProtocolNames:Unsupported', ...
            'Unsupported protocol: %s', key);
    end
    if ~any(strcmp(names, matched))
        names{end + 1} = matched; %#ok<AGROW>
    end
end
end

