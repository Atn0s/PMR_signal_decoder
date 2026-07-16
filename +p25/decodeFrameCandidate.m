function record = decodeFrameCandidate(y, candidate, cfg)
%DECODEFRAMECANDIDATE Decode one P25 frame-sync candidate.
if nargin < 3 || isempty(cfg), cfg = p25.config(); end
c = p25.constants();
record = [];
symbols = p25.recoverSymbolsFromFs(y, candidate, c.fsNidSymbols, ...
    'Sps', cfg.samplesPerSymbol);
if isempty(symbols), return; end
bits = p25.sliceSymbolsToBits(symbols);
try
    nidBits = p25.extractNidBits(bits);
    nid = p25.decodeNid(nidBits);
catch
    return;
end
frame = p25.frameInfoFromNid(nid);

lc = [];
hcw = [];
es = [];
src = 0;
dst = 0;
if any(frame.duid == [0, 5, 10])
    fullSymbols = p25.recoverSymbolsFromFs(y, candidate, c.lduSymbols, ...
        'Sps', cfg.samplesPerSymbol);
    if ~isempty(fullSymbols)
        fullBits = p25.sliceSymbolsToBits(fullSymbols);
        if frame.duid == 5
            lc = p25.decodeLdu1Lc(fullBits);
            if ~isempty(lc)
                src = lc.src;
                dst = lc.dst;
            end
        elseif frame.duid == 0
            hcw = p25.decodeHduHcw(fullBits);
            if ~isempty(hcw), dst = hcw.tgid; end
        elseif frame.duid == 10
            es = p25.decodeLdu2Es(fullBits);
        end
    end
end
record = struct('nid', nid, 'frame', frame, 'candidate', candidate, ...
    'bits', bits, 'src', src, 'dst', dst, 'lc', lc, 'hcw', hcw, 'es', es);
end
