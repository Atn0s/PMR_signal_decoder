function nid = decodeNid(bits)
%DECODENID Decode P25 NID.
c = p25.constants();
if numel(bits) ~= c.nidBits
    error('p25:decodeNid:BadLength', 'P25 NID must be exactly 64 bits.');
end
[info, corrected, validBch] = p25.bch6316Decode(bits);
nac = p25.bitsToInt(info(1:12));
duid = p25.bitsToInt(info(13:16));
if isKey(c.duidNames, duid)
    duidName = c.duidNames(duid);
else
    duidName = sprintf('UNKNOWN_0x%X', duid);
end
nid = struct( ...
    'nac', nac, ...
    'duid', duid, ...
    'duid_name', duidName, ...
    'valid_bch', validBch, ...
    'corrected', corrected, ...
    'raw_bits', bits(:).');
end
