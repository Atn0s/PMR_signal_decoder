function tf = cchUsable(record)
%CCHUSABLE True when a CCH record carries usable information.
tf = ~isempty(record) && (logical(record.crc_ok) || logical(record.hamming_ok));
end

