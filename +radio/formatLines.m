function lines = formatLines(pdus)
%FORMATLINES Format a PDU struct array as a cell array of strings.
pdus = radio.normalizePdus(pdus);
lines = cell(numel(pdus), 1);
for k = 1:numel(pdus)
    lines{k} = radio.formatPdu(pdus(k));
end
end

