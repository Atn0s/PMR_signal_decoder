function uniquePdus = deduplicatePdus(pdus)
%DEDUPLICATEPDUS Protocol-aware de-duplication.
pdus = radio.normalizePdus(pdus);
uniquePdus = struct([]);
if isempty(pdus)
    return;
end

seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
for k = 1:numel(pdus)
    key = radio.dedupKey(pdus(k));
    keyStr = jsonencode(key);
    if isKey(seen, keyStr)
        continue;
    end
    seen(keyStr) = true;
    if isempty(uniquePdus)
        uniquePdus = pdus(k);
    else
        uniquePdus(end + 1) = pdus(k); %#ok<AGROW>
    end
end
end

