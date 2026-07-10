function block = decodeUdchFacch2(bits, channelName)
%DECODEUDCHFACCH2 Decode a 348-bit NXDN UDCH or FACCH2 block.
if nargin < 2, channelName = 'UDCH'; end
c = nxdn.constants();
[decoded, codec] = nxdn.decodeChannel(bits, 12, 29, c.punctureFacch2, 406);
infoBits = decoded(1:184);
received = nxdn.bitsToInt(decoded(185:199));
computed = nxdn.crc15(infoBits);
tail = decoded(200:203);
block = nxdn.baseChannelBlock(upper(channelName), decoded, codec, received, computed, tail);
block.sr_bits = infoBits(1:8).';
block.structure = nxdn.bitsToInt(infoBits(1:2));
block.ran = nxdn.bitsToInt(infoBits(3:8));
block.layer3_bits = infoBits(9:184).';
block.ok = block.crc_ok && block.tail_ok;
end
