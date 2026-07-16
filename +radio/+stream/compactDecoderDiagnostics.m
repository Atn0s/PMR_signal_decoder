function compact = compactDecoderDiagnostics(diagnostics)
%COMPACTDECODERDIAGNOSTICS Keep bounded scalar diagnostics for IPC output.
% Protocol decoders may expose multi-megabyte training, slot, symbol, and
% bit arrays.  Those arrays are useful in an offline debug call but are not
% consumed by the real-time coordinator after evidence has been evaluated.
[compact, omittedCount, keep] = compactValue(diagnostics, 0);
if ~keep || ~isstruct(compact) || ~isscalar(compact)
    compact = struct();
end
compact.streamCompacted = true;
compact.streamOmittedValueCount = omittedCount;
end

function [out, omittedCount, keep] = compactValue(value, depth)
maxDepth = 4;
maxElements = 16;
maxTextLength = 256;
omittedCount = 0;
keep = false;
out = [];

if depth > maxDepth
    omittedCount = 1;
    return;
end
if isnumeric(value) || islogical(value)
    if numel(value) <= maxElements
        out = value;
        keep = true;
    else
        omittedCount = 1;
    end
    return;
end
if ischar(value)
    if numel(value) <= maxTextLength
        out = value;
        keep = true;
    else
        omittedCount = 1;
    end
    return;
end
if isstring(value)
    if isscalar(value) && strlength(value) <= maxTextLength
        out = value;
        keep = true;
    else
        omittedCount = 1;
    end
    return;
end
if isstruct(value)
    if ~isscalar(value)
        omittedCount = max(1, numel(value));
        return;
    end
    out = struct();
    names = fieldnames(value);
    for k = 1:numel(names)
        name = names{k};
        [child, childOmitted, childKeep] = ...
            compactValue(value.(name), depth + 1);
        omittedCount = omittedCount + childOmitted;
        if childKeep
            out.(name) = child;
        end
    end
    keep = true;
    return;
end

% Cells, objects, tables, function handles, and other debug-only values are
% intentionally omitted from the worker-to-client real-time message.
omittedCount = 1;
end
