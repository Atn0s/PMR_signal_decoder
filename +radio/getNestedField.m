function value = getNestedField(s, path, defaultValue)
%GETNESTEDFIELD Read nested struct fields from a dot-separated path.
if nargin < 3
    defaultValue = [];
end
value = s;
parts = strsplit(char(path), '.');
for k = 1:numel(parts)
    if ~isstruct(value) || ~isfield(value, parts{k})
        value = defaultValue;
        return;
    end
    value = value.(parts{k});
end
end

