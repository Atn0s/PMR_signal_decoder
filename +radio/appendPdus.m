function out = appendPdus(a, b)
%APPENDPDUS Append PDU struct arrays after aligning MATLAB struct fields.
if isempty(a)
    out = radio.normalizePdus(b);
    return;
elseif isempty(b)
    out = radio.normalizePdus(a);
    return;
end

a = radio.normalizePdus(a);
b = radio.normalizePdus(b);
fields = union(fieldnames(a), fieldnames(b));
a = ensureFields(a(:), fields);
b = ensureFields(b(:), fields);
out = [a; b].';
end

function items = ensureFields(items, fields)
for j = 1:numel(fields)
    field = fields{j};
    if isfield(items, field)
        continue;
    end
    for k = 1:numel(items)
        items(k).(field) = [];
    end
end
items = orderfields(items, fields);
end
