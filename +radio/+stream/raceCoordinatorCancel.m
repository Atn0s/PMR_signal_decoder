function [coordinator, report] = raceCoordinatorCancel(coordinator, varargin)
%RACECOORDINATORCANCEL Cancel every asynchronous task owned by a channel.
p = inputParser;
p.addParameter('Reason', 'coordinator_canceled');
p.parse(varargin{:});
reason = char(p.Results.Reason);

raceCanceled = false;
catchupCanceled = false;
decoderCanceled = false;
if ~isempty(coordinator.activeRace)
    [coordinator.activeRace, ~] = ...
        radio.stream.parallelProbeRaceCancel( ...
            coordinator.activeRace, 'Reason', reason);
    coordinator.activeRace = [];
    raceCanceled = true;
end
if ~isempty(coordinator.activeCatchup)
    [coordinator.activeCatchup, ~] = ...
        radio.stream.winnerCatchupCancel(coordinator.activeCatchup);
    coordinator.activeCatchup = [];
    catchupCanceled = true;
end
if ~isempty(coordinator.activeDecode)
    [coordinator.activeDecode, ~] = ...
        radio.stream.lockedDecoderCancel(coordinator.activeDecode);
    coordinator.activeDecode = [];
    decoderCanceled = true;
end

report = struct( ...
    'reason', reason, ...
    'raceCanceled', raceCanceled, ...
    'catchupCanceled', catchupCanceled, ...
    'decoderCanceled', decoderCanceled, ...
    'taskCount', double(raceCanceled) + double(catchupCanceled) + ...
        double(decoderCanceled));
end
