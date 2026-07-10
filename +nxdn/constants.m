function c = constants()
%CONSTANTS NXDN96 air-interface constants.
c = struct();
c.fswBits = logical([1 1 0 0 1 1 0 1 1 1 1 1 0 1 0 1 1 0 0 1]);
c.fswHex = 'CDF59';
c.fswLevels = [-3; 1; -3; 3; -3; -3; 3; 3; -1; 3];
c.levels = [-3; -1; 1; 3];
c.levelDibits = uint8([3; 2; 0; 1]);
c.pn9Seed = uint16(hex2dec('0E4'));
c.frameSymbols = 192;
c.fswSymbols = 10;
c.lichSymbols = 8;
c.scrambledSymbols = 182;
c.lichBitStart = 1;
c.lichBitEnd = 16;
c.sacchBitStart = 17;
c.sacchBitEnd = 76;
c.half1BitStart = 77;
c.half1BitEnd = 220;
c.half2BitStart = 221;
c.half2BitEnd = 364;
c.punctureSacch = logical([1 1 1 1 1 0 1 1 1 1 1 0]);
c.punctureFacch1 = logical([1 0 1 1]);
c.punctureFacch2 = logical([1 1 1 0 1 1 1 1 1 1 1 0 1 1]);
c.punctureCacOutbound = c.punctureFacch2;
c.punctureCacLongInbound = logical([1 0 1 1 1 1 1 0 1 0 1 0 1 1 1 1 1 0 1 1 1 1 1 1 1 1]);
c.punctureCacShortInbound = true(1, 2);
end
