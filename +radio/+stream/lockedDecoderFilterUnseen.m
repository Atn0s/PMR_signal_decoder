function [state, newPdus] = lockedDecoderFilterUnseen( ...
        state, pdus, retainedStartSample)
%LOCKEDDECODERFILTERUNSEEN Apply the streaming PDU ledger.
persistentMask = state.seenSamples == intmax('uint64');
keepMask = persistentMask | state.seenSamples >= retainedStartSample;
state.seenSamples = state.seenSamples(keepMask);
state.seenKeys = state.seenKeys(keepMask);
newPdus = struct([]);
for k = 1:numel(pdus)
    [key, isPersistent] = radio.stream.streamPduKey( ...
        pdus(k), state.sampleRateHz, ...
        'SemanticDeduplicate', state.semanticDeduplicate);
    if any(strcmp(state.seenKeys, key)), continue; end
    state.seenKeys{end+1, 1} = key;
    if isPersistent
        state.seenSamples(end+1, 1) = intmax('uint64');
    else
        state.seenSamples(end+1, 1) = radio.getNestedField( ...
            pdus(k), 'extra.stream.source_sample', uint64(0));
    end
    if isempty(newPdus)
        newPdus = pdus(k);
    else
        newPdus(end+1) = pdus(k); %#ok<AGROW>
    end
end
end
