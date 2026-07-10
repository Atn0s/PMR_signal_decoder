function [names, explicitProtocols] = resolveScanProtocols(protocolNames, varargin)
%RESOLVESCANPROTOCOLS Resolve requested protocols for the current scan mode.
p = inputParser;
p.addParameter('FreqList', []);
p.addParameter('BlindSearch', false);
p.parse(varargin{:});

explicitProtocols = hasExplicitProtocols(protocolNames);
if explicitProtocols
    names = radio.normalizeProtocolNames(protocolNames);
    return;
end

if p.Results.BlindSearch
    names = defaultProtocolsFor('defaultBlindSearch');
elseif ~isempty(p.Results.FreqList)
    names = defaultProtocolsFor('defaultFreqListScan');
else
    names = defaultProtocolsFor('defaultBasebandScan');
end
end

function tf = hasExplicitProtocols(protocolNames)
if nargin < 1 || isempty(protocolNames)
    tf = false;
elseif ischar(protocolNames)
    tf = ~isempty(strtrim(protocolNames));
elseif isstring(protocolNames)
    tf = any(strlength(protocolNames) > 0);
elseif iscell(protocolNames)
    tf = ~isempty(protocolNames);
else
    tf = true;
end
end

function names = defaultProtocolsFor(fieldName)
specs = radio.protocolRegistry();
names = {};
for k = 1:numel(specs)
    if isfield(specs(k), fieldName) && specs(k).(fieldName)
        names{end + 1} = specs(k).name; %#ok<AGROW>
    end
end
end
