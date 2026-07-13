function summary = summarizeProbeResults(results, epochId, generation)
%SUMMARIZEPROBERESULTS Resolve a set of same-generation probe results.
if nargin < 2 || isempty(epochId)
    epochId = results(1).epochId;
end
if nargin < 3 || isempty(generation)
    generation = results(1).generation;
end
if any([results.epochId] ~= uint64(epochId)) || ...
        any([results.generation] ~= uint64(generation))
    error('radio:stream:summarizeProbeResults:StaleResult', ...
        'All probe results must belong to the active epoch and generation.');
end

confirmed = find(strcmp({results.status}, 'confirmed'));
if numel(confirmed) == 1
    outcome = 'confirmed';
    winner = results(confirmed);
elseif numel(confirmed) > 1
    outcome = 'ambiguous';
    winner = [];
elseif all(strcmp({results.status}, 'rejected'))
    outcome = 'rejected_all';
    winner = [];
elseif any(strcmp({results.status}, 'error')) && ...
        all(ismember({results.status}, {'error', 'rejected'}))
    outcome = 'error';
    winner = [];
else
    outcome = 'classifying';
    winner = [];
end

summary = struct( ...
    'epochId', uint64(epochId), ...
    'generation', uint64(generation), ...
    'outcome', outcome, ...
    'winner', winner, ...
    'confirmedProtocols', {reshape({results(confirmed).protocol}, 1, [])}, ...
    'results', results);
end
