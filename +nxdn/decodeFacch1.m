function block = decodeFacch1(bits, halfIndex)
%DECODEFACCH1 Decode one 144-bit NXDN FACCH1 physical block.
if nargin < 2, halfIndex = 0; end
c = nxdn.constants();
[decoded, codec] = nxdn.decodeChannel(bits, 16, 9, c.punctureFacch1, 192);
infoBits = decoded(1:80);
received = nxdn.bitsToInt(decoded(81:92));
computed = nxdn.crc12(infoBits);
tail = decoded(93:96);
block = nxdn.baseChannelBlock('FACCH1', decoded, codec, received, computed, tail);
block.layer3_bits = infoBits(:).';
block.half_index = halfIndex;
block.ok = block.crc_ok && block.tail_ok;
end
