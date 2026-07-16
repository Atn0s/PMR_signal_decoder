function shadow = lockedDecoderActorShadow(state)
%LOCKEDDECODERACTORSHADOW Return only scheduler-visible decoder state.
shadow = state;
if isfield(shadow, 'actor'), shadow.actor = []; end
shadow.seenKeys = cell(0, 1);
shadow.seenSamples = zeros(0, 1, 'uint64');
if isfield(shadow, 'incremental')
    shadow.incremental.historyIq = complex(zeros(0, 1, 'single'));
    if isfield(shadow.incremental, 'nativeState')
        shadow.incremental.nativeState = [];
    end
    if isfield(shadow.incremental, 'nativeSeed')
        shadow.incremental.nativeSeed = [];
    end
    if isfield(shadow.incremental, 'lastDiagnostics')
        shadow.incremental.lastDiagnostics = ...
            radio.stream.compactDecoderDiagnostics( ...
                shadow.incremental.lastDiagnostics);
    end
end
end
