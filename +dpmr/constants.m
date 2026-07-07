function c = constants()
%CONSTANTS dPMR constants.
persistent cache
if ~isempty(cache)
    c = cache;
    return;
end
c = struct();
c.fsDec = 48000;
c.symbolRate = 2400;
c.sps = 20;
c.frameSymbols = 384;
c.cchSymbols = 36;
c.tchSymbols = 144;
c.ccSymbols = 12;
c.fs1Symbols = digits('111333331133131131111313');
c.fs2Symbols = digits('113333131331');
c.fs3Symbols = digits('133131333311');
c.fs4Symbols = digits('333111113311313313333131');
c.invFs1Symbols = digits('333111113311313313333131');
c.invFs2Symbols = digits('331111313113');
c.invFs3Symbols = digits('311313111133');
c.invFs4Symbols = digits('111333331133131131111313');
c.voiceFs2TotalSymbols = numel(c.fs2Symbols) + c.cchSymbols + c.tchSymbols + c.ccSymbols + c.cchSymbols + c.tchSymbols;
c.dibitLevels = [1, 3, -1, -3];
cache = c;
end

function out = digits(text)
out = double(char(text) - '0');
out = out(:).';
end

