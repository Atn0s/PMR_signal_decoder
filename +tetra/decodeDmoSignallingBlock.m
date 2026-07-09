function decoded = decodeDmoSignallingBlock(bits, kind, colourCodeBits, cfg)
%DECODEDMOSIGNALLINGBLOCK Decode DMO SCH/S, SCH/H, STCH, or SCH/F bits.
if nargin < 3 || isempty(colourCodeBits)
    colourCodeBits = zeros(30, 1) ~= 0;
end
if nargin < 4 || isempty(cfg)
    cfg = tetra.config();
end

p = blockParameters(kind);
bits = bits(:) ~= 0;
if numel(bits) ~= p.inputLength
    error('tetra:decodeDmoSignallingBlock:BadLength', ...
        '%s decoding expects exactly %d scrambled bits.', ...
        p.logicalChannel, p.inputLength);
end
colourCodeBits = colourCodeBits(:) ~= 0;
if numel(colourCodeBits) ~= 30
    error('tetra:decodeDmoSignallingBlock:BadColourCode', ...
        'DMO scrambling requires a 30-bit colour code.');
end

descrambled = xor(bits, tetra.scramblingSequence(p.inputLength, colourCodeBits));
type3Bits = tetra.blockDeinterleave(descrambled, p.interleaverA);
[type2Bits, rcpcInfo] = tetra.rcpcDecodeRate23(type3Bits, p.type2Length);
type1Bits = type2Bits(1:p.type1Length);
rxParity = type2Bits(p.type1Length + (1:16));
tailBits = type2Bits(p.type1Length + 17:end);
calcParity = tetra.dmoBlockCodeParity(type1Bits);
blockCodeErrors = nnz(rxParity ~= calcParity);
tailErrors = nnz(tailBits);

[blockLimit, tailLimit] = errorLimits(p.logicalChannel, cfg);
ok = blockCodeErrors <= blockLimit && tailErrors <= tailLimit;

decoded = struct();
decoded.logicalChannel = p.logicalChannel;
decoded.ok = ok;
decoded.inputBits = bits;
decoded.colourCodeBits = colourCodeBits;
decoded.descrambledBits = descrambled;
decoded.type3Bits = type3Bits;
decoded.type2Bits = type2Bits;
decoded.type1Bits = type1Bits;
decoded.parityBits = rxParity;
decoded.calculatedParityBits = calcParity;
decoded.tailBits = tailBits;
decoded.blockCodeErrors = blockCodeErrors;
decoded.tailErrors = tailErrors;
decoded.blockCodeErrorLimit = blockLimit;
decoded.tailErrorLimit = tailLimit;
decoded.rcpcMetric = rcpcInfo.metric;
decoded.rcpcFinalState = rcpcInfo.finalState;
decoded.rcpcEndedInZeroState = rcpcInfo.endedInZeroState;
decoded.type1Length = p.type1Length;
decoded.type2Length = p.type2Length;
decoded.type3Length = p.inputLength;
decoded.interleaverA = p.interleaverA;
end

function p = blockParameters(kind)
k = upper(strrep(strrep(strtrim(char(kind)), '-', '/'), ' ', ''));
switch k
    case {'SCH/S', 'SCHS'}
        p = makeParams('SCH/S', 120, 60, 80, 11);
    case {'SCH/H', 'SCHH'}
        p = makeParams('SCH/H', 216, 124, 144, 101);
    case 'STCH'
        p = makeParams('STCH', 216, 124, 144, 101);
    case {'SCH/F', 'SCHF'}
        p = makeParams('SCH/F', 432, 268, 288, 103);
    otherwise
        error('tetra:decodeDmoSignallingBlock:UnknownKind', ...
            'Unsupported DMO signalling block kind: %s.', char(kind));
end
end

function p = makeParams(name, inputLength, type1Length, type2Length, interleaverA)
p = struct( ...
    'logicalChannel', name, ...
    'inputLength', inputLength, ...
    'type1Length', type1Length, ...
    'type2Length', type2Length, ...
    'interleaverA', interleaverA);
end

function [blockLimit, tailLimit] = errorLimits(logicalChannel, cfg)
if strcmp(logicalChannel, 'SCH/S')
    blockLimit = getCfg(cfg, 'schSBlockCodeMaxErrors', ...
        getCfg(cfg, 'dmoSignallingBlockCodeMaxErrors', 0));
    tailLimit = getCfg(cfg, 'schSTailMaxErrors', ...
        getCfg(cfg, 'dmoSignallingTailMaxErrors', 0));
else
    blockLimit = getCfg(cfg, 'dmoSignallingBlockCodeMaxErrors', 0);
    tailLimit = getCfg(cfg, 'dmoSignallingTailMaxErrors', 0);
end
end

function value = getCfg(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
