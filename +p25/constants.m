function c = constants()
%CONSTANTS P25 Phase 1 constants and deinterleave layouts.
persistent cache
if ~isempty(cache)
    c = cache;
    return;
end

c = struct();
c.frameSyncHex = '5575F5FF77FF';
c.frameSyncBits = hexToBits(c.frameSyncHex);
c.dibitToSymbol = containers.Map({'00', '01', '10', '11'}, {1, 3, -1, -3});
c.duidNames = containers.Map( ...
    {0, 3, 5, 7, 10, 12, 15}, ...
    {'HDU', 'TDU', 'LDU1', 'TSBK', 'LDU2', 'PDU', 'TDULC'});
c.fsBits = 48;
c.nidBits = 64;
c.fsSymbols = 24;
c.nidAirSymbols = 33;
c.nidStatusSymbolOffset = 11;
c.fsNidSymbols = 57;
c.lduSymbols = 864;
c.frameSyncSymbols = dibitsToSymbols(c.frameSyncBits);
c.lcHexbitPositions = ldu1LcPositions(c);
c.esHexbitPositions = ldu2EsPositions(c);
[c.hduDataHexbitPositions, c.hduGolayParityPositions] = hduHexbitPositions(c);
cache = c;
end

function bits = hexToBits(hexStr)
bits = '';
for k = 1:numel(hexStr)
    bits = [bits dec2bin(hex2dec(hexStr(k)), 4)]; %#ok<AGROW>
end
end

function symbols = dibitsToSymbols(bits)
symbols = zeros(numel(bits) / 2, 1);
for k = 1:numel(symbols)
    pair = bits(2*k-1:2*k);
    switch pair
        case '00'
            symbols(k) = 1;
        case '01'
            symbols(k) = 3;
        case '10'
            symbols(k) = -1;
        otherwise
            symbols(k) = -3;
    end
end
end

function positions = ldu1LcPositions(c)
sym = (c.fsBits + c.nidBits) / 2;
statusCount = 21;
labels = containers.Map();

    function readDibit(label)
        if statusCount == 35
            sym = sym + 1;
            statusCount = 1;
        else
            statusCount = statusCount + 1;
        end
        sym = sym + 1;
        if nargin > 0 && ~isempty(label)
            if isKey(labels, label)
                labels(label) = [labels(label), sym * 2 + 1, sym * 2 + 2];
            else
                labels(label) = [sym * 2 + 1, sym * 2 + 2];
            end
        end
    end

    function imbe()
        for ii = 1:72
            readDibit('');
        end
    end

    function hexword(label)
        for ii = 1:5
            readDibit(label);
        end
    end

imbe(); imbe();
for i = [11 10 9 8], hexword(sprintf('d%d', i)); end
imbe();
for i = [7 6 5 4], hexword(sprintf('d%d', i)); end
imbe();
for i = [3 2 1 0], hexword(sprintf('d%d', i)); end
imbe();
for i = [11 10 9 8], hexword(sprintf('p%d', i)); end
imbe();
for i = [7 6 5 4], hexword(sprintf('p%d', i)); end
imbe();
for i = [3 2 1 0], hexword(sprintf('p%d', i)); end

positions = [];
for typ = ["d", "p"]
    for i = 0:11
        positions = [positions, labels(sprintf('%s%d', typ, i))]; %#ok<AGROW>
    end
end
end

function positions = ldu2EsPositions(c)
sym = (c.fsBits + c.nidBits) / 2;
statusCount = 21;
labels = containers.Map();

    function readDibit(label)
        if statusCount == 35
            sym = sym + 1;
            statusCount = 1;
        else
            statusCount = statusCount + 1;
        end
        sym = sym + 1;
        if nargin > 0 && ~isempty(label)
            if isKey(labels, label)
                labels(label) = [labels(label), sym * 2 + 1, sym * 2 + 2];
            else
                labels(label) = [sym * 2 + 1, sym * 2 + 2];
            end
        end
    end

    function imbe()
        for ii = 1:72
            readDibit('');
        end
    end

    function hexword(label)
        for ii = 1:5
            readDibit(label);
        end
    end

imbe(); imbe();
for i = [15 14 13 12], hexword(sprintf('d%d', i)); end
imbe();
for i = [11 10 9 8], hexword(sprintf('d%d', i)); end
imbe();
for i = [7 6 5 4], hexword(sprintf('d%d', i)); end
imbe();
for i = [3 2 1 0], hexword(sprintf('d%d', i)); end
imbe();
for i = [7 6 5 4], hexword(sprintf('p%d', i)); end
imbe();
for i = [3 2 1 0], hexword(sprintf('p%d', i)); end

positions = [];
for typCount = 1:2
    if typCount == 1
        typ = 'd'; count = 16;
    else
        typ = 'p'; count = 8;
    end
    for i = 0:count-1
        positions = [positions, labels(sprintf('%s%d', typ, i))]; %#ok<AGROW>
    end
end
end

function [dataPositions, parityPositions] = hduHexbitPositions(c)
sym = (c.fsBits + c.nidBits) / 2;
statusCount = 21;
dataLabels = containers.Map('KeyType', 'double', 'ValueType', 'any');
golayLabels = containers.Map('KeyType', 'double', 'ValueType', 'any');

    function readDibit(kind, label)
        if statusCount == 35
            sym = sym + 1;
            statusCount = 1;
        else
            statusCount = statusCount + 1;
        end
        sym = sym + 1;
        target = [sym * 2 + 1, sym * 2 + 2];
        if kind == 'g'
            if isKey(golayLabels, label)
                golayLabels(label) = [golayLabels(label), target];
            else
                golayLabels(label) = target;
            end
        else
            if isKey(dataLabels, label)
                dataLabels(label) = [dataLabels(label), target];
            else
                dataLabels(label) = target;
            end
        end
    end

    function readBits(bitCount, kind, label)
        for ii = 1:(bitCount / 2)
            readDibit(kind, label);
        end
    end

for i = 19:-1:0
    readBits(6, 'd', i);
    readBits(12, 'g', i);
end
for i = 15:-1:0
    readBits(6, 'r', i + 20);
    readBits(12, 'g', i + 20);
end

dataPositions = [];
parityPositions = [];
for i = 0:35
    dataPositions = [dataPositions, dataLabels(i)]; %#ok<AGROW>
    parityPositions = [parityPositions, golayLabels(i)]; %#ok<AGROW>
end
end

