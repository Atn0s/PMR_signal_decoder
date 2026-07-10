function lich = decodeLich(dibits, cfg)
%DECODELICH Decode the eight scrambled LICH dibits.
if nargin < 2 || isempty(cfg)
    cfg = nxdn.config();
end
if numel(dibits) ~= 8
    error('nxdn:decodeLich:BadLength', 'LICH requires 8 dibits.');
end
decoded = nxdn.descrambleDibits(dibits);
infoBits = bitget(decoded, 2) ~= 0;
fillBits = bitget(decoded, 1) ~= 0;
fullValue = nxdn.bitsToInt(infoBits);
receivedParity = bitand(fullValue, 1);
computedParity = mod(sum(double(infoBits(1:4))), 2);
lich = struct();
lich.full_value = fullValue;
lich.value = floor(fullValue / 2);
lich.info_bits = logical(infoBits(:).');
lich.fill_bits = logical(fillBits(:).');
lich.fill_count = nnz(fillBits);
lich.received_parity = receivedParity;
lich.computed_parity = computedParity;
lich.parity_ok = receivedParity == computedParity;
lich.fill_bits_ok = lich.fill_count >= cfg.lichMinFillBits;
lich.ok = lich.parity_ok && lich.fill_bits_ok;
lich.dibits = decoded(:).';
end
