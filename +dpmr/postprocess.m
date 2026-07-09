function filtered = postprocess(pdus)
%POSTPROCESS Keep quality/stable dPMR color-code PDUs and matching calls.
pdus = radio.normalizePdus(pdus);
cfg = dpmr.config();
if isempty(pdus)
    filtered = pdus;
    return;
end

frameIdx = [];
for k = 1:numel(pdus)
    if strcmp(char(radio.getField(pdus(k), 'protocol', '')), 'dPMR') && ...
            ~strcmp(char(radio.getField(pdus(k), 'type', '')), 'dPMR_CALL')
        frameIdx(end + 1) = k; %#ok<AGROW>
    end
end
if numel(frameIdx) < cfg.stableColorMinRepeats
    filtered = pdus;
    return;
end

[stable, repeats, ok] = chooseStableColor(pdus, frameIdx);
if ~ok || repeats < cfg.stableColorMinRepeats
    filtered = pdus;
    return;
end
hasHighOrMedium = any(arrayfun(@(idx) ...
    sameColor(pdus(idx), stable) && highOrMedium(pdus(idx)), frameIdx));

filtered = struct([]);
for k = 1:numel(pdus)
    if ~strcmp(char(radio.getField(pdus(k), 'protocol', '')), 'dPMR')
        filtered = appendOne(filtered, pdus(k));
        continue;
    end
    typ = char(radio.getField(pdus(k), 'type', ''));
    if strcmp(typ, 'dPMR_CALL') && sameColor(pdus(k), stable)
        pdus(k).extra.stable_color_code = stable;
        pdus(k).extra.stable_color_repeats = repeats;
        filtered = appendOne(filtered, pdus(k));
    elseif sameColor(pdus(k), stable) && (~hasHighOrMedium || highOrMedium(pdus(k)))
        pdus(k).extra.stable_color_code = stable;
        pdus(k).extra.stable_color_repeats = repeats;
        filtered = appendOne(filtered, pdus(k));
    end
end
end

function [stable, repeats, ok] = chooseStableColor(pdus, frameIdx)
colors = [];
firstSeen = [];
qualityScores = [];
for n = 1:numel(frameIdx)
    k = frameIdx(n);
    cc = radio.getNestedField(pdus(k), 'extra.color_code', []);
    if isempty(cc) || double(cc) < 0
        continue;
    end
    cc = double(cc);
    idx = find(colors == cc, 1);
    if isempty(idx)
        colors(end+1) = cc; %#ok<AGROW>
        firstSeen(end+1) = n; %#ok<AGROW>
        qualityScores(end+1) = qualityScore(pdus(k)); %#ok<AGROW>
    else
        qualityScores(idx) = qualityScores(idx) + qualityScore(pdus(k));
    end
end
if isempty(colors)
    stable = NaN;
    repeats = 0;
    ok = false;
    return;
end
counts = arrayfun(@(cc) countColor(pdus, frameIdx, cc), colors);
rank = [counts(:), -firstSeen(:), qualityScores(:)];
[~, best] = maxRows(rank);
stable = colors(best);
repeats = counts(best);
ok = true;
end

function n = countColor(pdus, frameIdx, color)
n = 0;
for k = frameIdx(:).'
    if sameColor(pdus(k), color)
        n = n + 1;
    end
end
end

function [value, idx] = maxRows(rank)
idx = 1;
for k = 2:size(rank, 1)
    if lexGreater(rank(k, :), rank(idx, :))
        idx = k;
    end
end
value = rank(idx, :);
end

function yes = lexGreater(a, b)
yes = false;
for k = 1:numel(a)
    if a(k) > b(k)
        yes = true;
        return;
    elseif a(k) < b(k)
        return;
    end
end
end

function yes = sameColor(pdu, color)
cc = radio.getNestedField(pdu, 'extra.color_code', []);
yes = ~isempty(cc) && double(cc) == double(color);
end

function yes = highOrMedium(pdu)
conf = confidence(pdu);
yes = any(strcmp(conf, {'high', 'medium'}));
end

function score = qualityScore(pdu)
switch confidence(pdu)
    case 'high'
        score = 10;
    case 'medium'
        score = 6;
    case 'low'
        score = 1;
    otherwise
        score = 0;
end
end

function text = confidence(pdu)
text = radio.getNestedField(pdu, 'extra.quality.front_end_confidence', '');
if isempty(text)
    text = radio.getNestedField(pdu, 'extra.quality.confidence', 'none');
end
text = char(text);
end

function out = appendOne(arr, item)
if isempty(arr)
    out = item;
else
    out = arr;
    out(end + 1) = item;
end
end
