function out = deduplicatePdus(pdus)
%DEDUPLICATEPDUS Keep the first PDU for each NXDN semantic key.
if isempty(pdus), out = pdus; return; end
seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
keep = false(1, numel(pdus));
for k = 1:numel(pdus)
    text = jsonencode(nxdn.dedupKey(pdus(k)));
    if ~isKey(seen, text)
        seen(text) = true;
        keep(k) = true;
    end
end
out = pdus(keep);
end
