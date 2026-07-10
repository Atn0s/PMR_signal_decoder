function block = decodeSacch(bits, frameInfo)
%DECODESACCH Decode one 60-bit NXDN SACCH physical block.
c = nxdn.constants();
[decoded, codec] = nxdn.decodeChannel(bits, 12, 5, c.punctureSacch, 72);
infoBits = decoded(1:26);
received = nxdn.bitsToInt(decoded(27:32));
computed = nxdn.crc6(infoBits);
tail = decoded(33:36);
block = nxdn.baseChannelBlock('SACCH', decoded, codec, received, computed, tail);
block.sr_bits = infoBits(1:8).';
block.structure = nxdn.bitsToInt(infoBits(1:2));
block.ran = nxdn.bitsToInt(infoBits(3:8));
block.layer3_bits = infoBits(9:26).';
block.superframe = frameInfo.superframe;
block.ok = block.crc_ok && block.tail_ok;
end
