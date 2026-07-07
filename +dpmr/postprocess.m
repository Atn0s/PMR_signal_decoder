function filtered = postprocess(pdus)
%POSTPROCESS Keep repeated/stable dPMR color-code PDUs.
pdus = radio.normalizePdus(pdus);
cfg = dpmr.config();
if isempty(pdus)
    filtered = pdus;
    return;
end

colors = [];
for k = 1:numel(pdus)
    if strcmp(char(radio.getField(pdus(k), 'protocol', '')), 'dPMR')
        cc = radio.getNestedField(pdus(k), 'extra.color_code', []);
        if ~isempty(cc)
            colors(end + 1) = double(cc); %#ok<AGROW>
        end
    end
end
if isempty(colors)
    filtered = pdus;
    return;
end

uniqueColors = unique(colors);
counts = arrayfun(@(cc) sum(colors == cc), uniqueColors);
[maxCount, idx] = max(counts);
stable = uniqueColors(idx);

filtered = struct([]);
for k = 1:numel(pdus)
    if ~strcmp(char(radio.getField(pdus(k), 'protocol', '')), 'dPMR')
        filtered = appendOne(filtered, pdus(k));
        continue;
    end
    cc = radio.getNestedField(pdus(k), 'extra.color_code', []);
    if maxCount >= cfg.stableColorMinRepeats && ~isempty(cc) && double(cc) == stable
        pdus(k).extra.stable_color_code = stable;
        filtered = appendOne(filtered, pdus(k));
    elseif maxCount < cfg.stableColorMinRepeats
        filtered = appendOne(filtered, pdus(k));
    end
end
end

function out = appendOne(arr, item)
if isempty(arr)
    out = item;
else
    out = arr;
    out(end + 1) = item;
end
end

