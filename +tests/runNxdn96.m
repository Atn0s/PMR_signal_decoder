function report = runNxdn96()
%RUNNXDN96 NXDN96 unit and optional local-sample regression tests.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
cfg = nxdn.config();
c = nxdn.constants();
assert(any(strcmp({radio.protocolRegistry().name}, 'NXDN')));
assert(isequal(radio.normalizeProtocolNames({'nxdn96'}), {'NXDN'}));
assert(strcmp(c.fswHex, 'CDF59'));
assert(isequal(char(nxdn.pn9Sequence(8).' + '0'), '00100111'));
roundTrip = uint8(mod((0:181).', 4));
assert(isequal(nxdn.descrambleDibits(nxdn.descrambleDibits(roundTrip)), roundTrip));
for value = [hex2dec('50'), hex2dec('56'), hex2dec('40')]
    encoded = encodeLich(value);
    lich = nxdn.decodeLich(encoded, cfg);
    assert(lich.ok && lich.value == value);
end

assert(nxdn.crc6(false(26, 1)) == hex2dec('2B'));
assert(nxdn.crc12(false(80, 1)) == hex2dec('891'));
assert(nxdn.crc15(false(184, 1)) == hex2dec('456F'));

frameInfo = struct('superframe', true);
info26 = [nxdn.intToBits(3, 2); nxdn.intToBits(40, 6); logical(mod((1:18).', 3) == 0)];
decoded36 = [info26; nxdn.intToBits(nxdn.crc6(info26), 6); false(4, 1)];
sacchPhysical = channelEncode(decoded36, 12, 5, c.punctureSacch);
sacch = nxdn.decodeSacch(sacchPhysical, frameInfo);
assert(sacch.ok && sacch.ran == 40 && sacch.structure == 3);

vcall = hexBits('01002204B30000000000');
decoded96 = [vcall; nxdn.intToBits(nxdn.crc12(vcall), 12); false(4, 1)];
facchPhysical = channelEncode(decoded96, 16, 9, c.punctureFacch1);
facch = nxdn.decodeFacch1(facchPhysical, 1);
assert(facch.ok && isequal(facch.layer3_bits(:), vcall));
damaged = facchPhysical; damaged(1) = ~damaged(1);
badFacch = nxdn.decodeFacch1(damaged, 1);
assert(~badFacch.ok || badFacch.codec.viterbi.metric > 0);

f2Layer = logical(mod((1:176).', 5) < 2);
f2Info = [nxdn.intToBits(0, 2); nxdn.intToBits(17, 6); f2Layer];
f2Decoded = [f2Info; nxdn.intToBits(nxdn.crc15(f2Info), 15); false(4, 1)];
f2Physical = channelEncode(f2Decoded, 12, 29, c.punctureFacch2);
f2 = nxdn.decodeUdchFacch2(f2Physical, 'UDCH');
assert(f2.ok && f2.ran == 17 && isequal(f2.layer3_bits(:), f2Layer));

testCac('CAC_OUTBOUND', 144, 3, 12, 25, c.punctureCacOutbound);
testCac('CAC_LONG_INBOUND', 128, 0, 12, 21, c.punctureCacLongInbound);
testCac('CAC_SHORT_INBOUND', 96, 2, 12, 21, c.punctureCacShortInbound);

state = nxdn.sacchAssemblerInit();
assembled = [];
fullMessage = hexBits('01002204B300000000');
for part = 1:4
    block = sacch;
    block.structure = 4 - part;
    block.layer3_bits = fullMessage(18*part-17:18*part).';
    block.ok = true;
    fi = struct('superframe', true, 'direction', 'inbound', ...
        'rf_channel_type', 'RDCH');
    [state, item] = nxdn.sacchAssemblerFeed(state, block, fi, 1000+(part-1)*1920, cfg);
    if ~isempty(item), assembled = item; end
end
assert(~isempty(assembled) && isequal(assembled.layer3_bits(:), fullMessage));

context = struct('ran', 40, 'rf_channel_type', 'RDCH', ...
    'functional_channel', 'FACCH1', 'direction', 'inbound', ...
    'lich', hex2dec('50'), 'fs_start', 100, 'frame_index', 1);
pdu = nxdn.parseLayer3(vcall, context);
assert(strcmp(pdu.type, 'NXDN_VCALL'));
assert(pdu.src == 1203 && pdu.dst == 0);
assert(strcmp(pdu.extra.call_type, 'conference_group'));
assert(pdu.extra.transmission_mode == 2 && pdu.extra.ran == 40);
unknown = vcall; unknown(3:8) = nxdn.intToBits(62, 6);
unknownPdu = nxdn.parseLayer3(unknown, context);
assert(strcmp(unknownPdu.type, 'NXDN_L3_UNKNOWN'));

[noisePdus, noiseReport] = nxdn.decode(zeros(6000, 1), cfg);
assert(isempty(noisePdus) && noiseReport.validFrameCount == 0);

items = repmat(struct('file', '', 'skipped', false, 'pdu_count', 0, ...
    'call_count', 0, 'valid_frame_count', 0, 'valid_block_count', 0), 0, 1);
for sampleIndex = 1:2
    path = fullfile(root, 'signal_data', sprintf('nxdn96_%d_78125.rawiq', sampleIndex));
    item = struct('file', path, 'skipped', false, 'pdu_count', 0, ...
        'call_count', 0, 'valid_frame_count', 0, 'valid_block_count', 0);
    if exist(path, 'file') ~= 2
        item.skipped = true;
        items(end+1, 1) = item; %#ok<AGROW>
        fprintf('[SKIP] NXDN96 local sample %d is not present.\n', sampleIndex);
        continue;
    end
    iq = common.readRawIq(path);
    [pdus, decodedReport] = nxdn.decodeIq(iq, 78125, cfg);
    scannerRaw = radio.scanFile(path, 'ProtocolNames', {'nxdn'}, ...
        'ExecutionMode', 'parallel', ...
        'Deduplicate', false);
    assert(numel(scannerRaw) == numel(pdus));
    assert(isequal(sort(pduSignatures(scannerRaw)), sort(pduSignatures(pdus))));
    scannerDedup = radio.deduplicatePdus(scannerRaw);
    standaloneDedup = nxdn.deduplicatePdus(pdus);
    assert(isequal(sort(pduSignatures(scannerDedup)), ...
        sort(pduSignatures(standaloneDedup))));
    lines = radio.formatLines(scannerDedup);
    assert(all(contains(lines, 'PROTO=NXDN')));
    if sampleIndex == 1
        defaultRaw = radio.scanFile(path, ...
            'ExecutionMode', 'parallel', ...
            'Deduplicate', false);
        assert(~isempty(defaultRaw));
        assert(all(strcmp({defaultRaw.protocol}, 'NXDN')));
        assert(isequal(sort(pduSignatures(defaultRaw)), ...
            sort(pduSignatures(scannerRaw))));
        crop = iq(round(1.2 * 78125):round(1.7 * 78125));
        blindOffsets = radio.psdBlindSearch(crop, 78125, radio.defaultConfig());
        assert(numel(blindOffsets) == 1 && abs(blindOffsets(1)) < 1000);
    end
    vcalls = pdus(strcmp({pdus.type}, 'NXDN_VCALL'));
    calls = pdus(strcmp({pdus.type}, 'NXDN_CALL'));
    assert(~isempty(vcalls) && all([vcalls.src] == 1203));
    assert(all(arrayfun(@(x) radio.getNestedField(x, 'extra.ran', -1) == 40, vcalls)));
    assert(numel(calls) == 4);
    assert(all(arrayfun(@(x) strcmp(radio.getNestedField(x, 'extra.alias', ''), 'WM 3'), calls)));
    assert(decodedReport.validFrameCount >= 500);
    assert(decodedReport.validChannelBlockCount >= 1000);
    item.pdu_count = numel(pdus);
    item.call_count = numel(calls);
    item.valid_frame_count = decodedReport.validFrameCount;
    item.valid_block_count = decodedReport.validChannelBlockCount;
    if sampleIndex == 1
        displayPdus = nxdn.deduplicatePdus(pdus);
        assert(numel(displayPdus) >= 10 && numel(displayPdus) < numel(pdus));
        jsonPath = [tempname '.json'];
        cleaner = onCleanup(@() deleteIfPresent(jsonPath));
        radio.writeJson(displayPdus, jsonPath);
        assert(~contains(fileread(jsonPath), 'raw_bits'));
        radio.writeJson(displayPdus, jsonPath, 'IncludeRawBits', true);
        assert(contains(fileread(jsonPath), 'raw_bits'));
    end
    items(end+1, 1) = item; %#ok<AGROW>
    fprintf('[ OK ] NXDN96 sample %d: PDU=%d CALL=%d frames=%d blocks=%d\n', ...
        sampleIndex, item.pdu_count, item.call_count, ...
        item.valid_frame_count, item.valid_block_count);
end

report = struct('ok', true, 'samples', items);
fprintf('NXDN96 standalone tests passed.\n');
end

function dibits = encodeLich(value)
bits7 = nxdn.intToBits(value, 7);
parity = mod(sum(double(bits7(1:4))), 2);
bits = [bits7; logical(parity)];
dibits = uint8(ones(8, 1));
dibits(bits) = uint8(3);
dibits = nxdn.descrambleDibits(dibits);
end

function physical = channelEncode(decoded, rows, depth, puncture)
coded = convolutionEncode(decoded);
mask = false(size(coded));
for k = 1:numel(coded)
    mask(k) = puncture(mod(k-1, numel(puncture)) + 1);
end
punctured = coded(mask);
assert(numel(punctured) == rows * depth);
physical = false(size(punctured));
k = 1;
for row = 0:rows-1
    for column = 0:depth-1
        physical(k) = punctured(row + rows * column + 1);
        k = k + 1;
    end
end
end

function coded = convolutionEncode(bits)
bits = logical(bits(:));
state = false(1, 4);
coded = false(2*numel(bits), 1);
for k = 1:numel(bits)
    u = bits(k);
    coded(2*k-1) = xor(xor(u, state(3)), state(4));
    coded(2*k) = xor(xor(xor(u, state(1)), state(2)), state(4));
    state = [u state(1:3)];
end
end

function testCac(kind, layerLength, nullCount, rows, depth, puncture)
sr = [nxdn.intToBits(0, 2); nxdn.intToBits(22, 6)];
layer = logical(mod((1:layerLength).', 7) < 3);
data = [sr; layer; false(nullCount, 1)];
check = cacCheckBits(data);
decoded = [data; check; false(4, 1)];
physical = channelEncode(decoded, rows, depth, puncture);
block = nxdn.decodeCac(physical, kind);
assert(block.ok && block.ran == 22 && isequal(block.layer3_bits(:), layer));
end

function check = cacCheckBits(data)
zero = false(16, 1);
base = nxdn.intToBits(nxdn.crc16Cac([data; zero]), 16);
matrix = false(16, 16);
for column = 1:16
    probe = zero; probe(column) = true;
    effect = nxdn.intToBits(nxdn.crc16Cac([data; probe]), 16);
    matrix(:, column) = xor(effect, base);
end
check = solveGf2(matrix, base);
assert(nxdn.crc16Cac([data; check]) == 0);
end

function x = solveGf2(a, b)
aug = [logical(a) logical(b(:))];
n = size(a, 1);
for column = 1:n
    pivot = find(aug(column:end, column), 1) + column - 1;
    assert(~isempty(pivot));
    if pivot ~= column
        temp = aug(column, :); aug(column, :) = aug(pivot, :); aug(pivot, :) = temp;
    end
    for row = 1:n
        if row ~= column && aug(row, column)
            aug(row, :) = xor(aug(row, :), aug(column, :));
        end
    end
end
x = aug(:, end);
end

function bits = hexBits(text)
bits = false(4*numel(text), 1);
for k = 1:numel(text)
    value = hex2dec(text(k));
    bits(4*k-3:4*k) = nxdn.intToBits(value, 4);
end
end

function deleteIfPresent(path)
if exist(path, 'file') == 2, delete(path); end
end

function signatures = pduSignatures(pdus)
signatures = cell(numel(pdus), 1);
for k = 1:numel(pdus)
    signatures{k} = jsonencode({ ...
        radio.getField(pdus(k), 'protocol', ''), ...
        radio.getField(pdus(k), 'type', ''), ...
        radio.getField(pdus(k), 'src', 0), ...
        radio.getField(pdus(k), 'dst', 0), ...
        radio.getNestedField(pdus(k), 'extra.ran', []), ...
        radio.getNestedField(pdus(k), 'extra.payload_hex', '')});
end
end
