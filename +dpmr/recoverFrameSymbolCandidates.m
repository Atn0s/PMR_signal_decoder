function candidates = recoverFrameSymbolCandidates(y, syncCandidate, varargin)
%RECOVERFRAMESYMBOLCANDIDATES Recover dPMR symbol candidates.
p = inputParser;
p.addParameter('TotalSymbols', dpmr.constants().frameSymbols);
p.addParameter('PhaseSearch', linspace(-12, 12, 25));
p.addParameter('SpsSearch', dpmr.constants().sps);
p.addParameter('SampleWindows', 0);
p.addParameter('Limit', 8);
p.addParameter('DecisionAmbiguousThreshold', 0.35);
p.parse(varargin{:});

c = dpmr.constants();
refDibits = syncRef(syncCandidate);
ref = dpmr.dibitsToLevels(refDibits);
y = y(:);
items = struct([]);
for sps = p.Results.SpsSearch
    for phase = p.Results.PhaseSearch
        pos = syncCandidate.fs_start + phase + (0:p.Results.TotalSymbols-1).' .* double(sps);
        if pos(1) < 0 || pos(end) >= numel(y) - 1
            continue;
        end
        for sampleWindow = p.Results.SampleWindows
            if pos(1) - sampleWindow < 0 || pos(end) + sampleWindow >= numel(y) - 1
                continue;
            end
            seg = sampleSymbols(y, pos, sampleWindow);
            fsSeg = seg(1:numel(ref));
            coeff = [fsSeg, ones(numel(fsSeg), 1)] \ ref(:);
            calibrated = coeff(1) .* seg + coeff(2);
            [~, nearest] = min(abs(calibrated(:) - c.dibitLevels), [], 2);
            nearest = nearest(:).' - 1;
            decisionError = abs(calibrated(:).' - c.dibitLevels(nearest + 1));
            resid = mean((calibrated(1:numel(ref)) - ref(:)) .^ 2);
            resid = resid + 0.03 * mean((calibrated(:).' - c.dibitLevels(nearest + 1)) .^ 2);
            if syncCandidate.polarity_inverted
                nearest = bitxor(uint8(nearest), uint8(2));
                nearest = double(nearest);
            end
            item = struct('symbols', nearest, 'resid', resid, 'sps', double(sps), ...
                'phase', double(phase), 'sample_window', double(sampleWindow), ...
                'decision_error_p90', percentile(decisionError, 90), ...
                'ambiguous_symbols', sum(decisionError > p.Results.DecisionAmbiguousThreshold));
            items = appendStruct(items, item);
        end
    end
end
if isempty(items)
    candidates = struct([]);
    return;
end
[~, order] = sort([items.resid]);
items = items(order);
candidates = items(1:min(numel(items), p.Results.Limit));
end

function ref = syncRef(candidate)
c = dpmr.constants();
key = sprintf('%s_%d', candidate.sync_type, candidate.polarity_inverted);
switch key
    case 'FS1_0', ref = c.fs1Symbols;
    case 'FS2_0', ref = c.fs2Symbols;
    case 'FS3_0', ref = c.fs3Symbols;
    case 'FS4_0', ref = c.fs4Symbols;
    case 'FS1_1', ref = c.invFs1Symbols;
    case 'FS2_1', ref = c.invFs2Symbols;
    case 'FS3_1', ref = c.invFs3Symbols;
    otherwise, ref = c.invFs4Symbols;
end
end

function seg = sampleSymbols(y, pos, halfWindow)
if halfWindow <= 0
    seg = common.interpLinear(y, pos);
    return;
end
offsets = -halfWindow:halfWindow;
samples = zeros(numel(pos), numel(offsets));
for k = 1:numel(offsets)
    samples(:, k) = common.interpLinear(y, pos + offsets(k));
end
seg = mean(samples, 2);
end

function out = percentile(x, pct)
x = sort(x(:));
if isempty(x), out = NaN; return; end
pos = 1 + (numel(x) - 1) * pct / 100;
lo = floor(pos); hi = ceil(pos);
if lo == hi
    out = x(lo);
else
    out = x(lo) * (hi - pos) + x(hi) * (pos - lo);
end
end

function out = appendStruct(arr, item)
if isempty(arr), out = item; else, out = arr; out(end + 1) = item; end
end

