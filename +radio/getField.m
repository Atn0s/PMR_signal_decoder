function value = getField(s, name, defaultValue)
%GETFIELD Read a struct field with compatibility aliases.
if nargin < 3
    defaultValue = [];
end
if ~isstruct(s)
    value = defaultValue;
    return;
end

aliases = {name};
if strcmp(name, '_fo_hz')
    aliases = {'_fo_hz', 'x_fo_hz', 'fo_hz'};
elseif strcmp(name, 'fo_hz')
    aliases = {'fo_hz', '_fo_hz', 'x_fo_hz'};
end

for k = 1:numel(aliases)
    if isfield(s, aliases{k})
        value = s.(aliases{k});
        return;
    end
end
value = defaultValue;
end

