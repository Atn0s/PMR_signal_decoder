function [tracker, update] = candidateTrackerFeed( ...
        tracker, detections, batch)
%CANDIDATETRACKERFEED Track fine-frequency candidates across PFB batches.
events = emptyEvents();
closedTracks = radio.wideband.emptyTrack();
closedTracks = closedTracks([]);
durationSec = size(batch.iq, 2) / batch.sampleRateHz;

if batch.discontinuity || ...
        batch.continuityGeneration ~= tracker.continuityGeneration
    for index = 1:numel(tracker.tracks)
        closedTracks(end+1, 1) = tracker.tracks(index); %#ok<AGROW>
        events(end+1, 1) = makeEvent('TRACK_CLOSED', ...
            tracker.tracks(index), 'input_discontinuity'); %#ok<AGROW>
    end
    tracker.tracks = tracker.tracks([]);
    tracker.continuityGeneration = uint64(batch.continuityGeneration);
end

matchedTracks = false(1, numel(tracker.tracks));
matchedDetections = false(1, numel(detections));
if ~isempty(detections) && ~isempty(tracker.tracks)
    [~, detectionOrder] = sort([detections.snrDb], 'descend');
    for detectionIndex = detectionOrder
        distances = abs([tracker.tracks.frequencyOffsetHz] - ...
            detections(detectionIndex).frequencyOffsetHz);
        distances(matchedTracks) = inf;
        [distance, trackIndex] = min(distances);
        if distance <= tracker.config.matchToleranceHz
            matchedTracks(trackIndex) = true;
            matchedDetections(detectionIndex) = true;
            [tracker.tracks(trackIndex), nextEvents] = updateMatched( ...
                tracker.tracks(trackIndex), detections(detectionIndex), ...
                durationSec, tracker.config);
            events = [events; nextEvents]; %#ok<AGROW>
        end
    end
end

for trackIndex = numel(tracker.tracks):-1:1
    if matchedTracks(trackIndex)
        continue;
    end
    track = tracker.tracks(trackIndex);
    track.missingDurationSec = track.missingDurationSec + durationSec;
    track.continuousOnSec = 0;
    if strcmp(track.state, 'active')
        track.state = 'off_pending';
        events(end+1, 1) = makeEvent( ...
            'TRACK_OFF_PENDING', track, 'carrier_not_observed'); %#ok<AGROW>
    end
    if strcmp(track.state, 'tentative')
        closeNow = track.missingDurationSec >= tracker.config.minOnSec;
    else
        closeNow = track.missingDurationSec >= tracker.config.offHangSec;
    end
    if closeNow
        closedTracks(end+1, 1) = track; %#ok<AGROW>
        events(end+1, 1) = makeEvent( ...
            'TRACK_CLOSED', track, 'carrier_off_hang_elapsed'); %#ok<AGROW>
        tracker.tracks(trackIndex) = [];
        matchedTracks(trackIndex) = [];
    else
        tracker.tracks(trackIndex) = track;
    end
end

for detectionIndex = find(~matchedDetections)
    track = newTrack(tracker.nextTrackId, detections(detectionIndex), ...
        durationSec);
    tracker.nextTrackId = tracker.nextTrackId + uint64(1);
    tracker.tracks(end+1, 1) = track;
    events(end+1, 1) = makeEvent( ...
        'TRACK_STARTED', track, 'new_frequency_candidate'); %#ok<AGROW>
    if track.continuousOnSec >= tracker.config.minOnSec
        tracker.tracks(end).state = 'active';
        tracker.tracks(end).isConfirmed = true;
        events(end+1, 1) = makeEvent( ...
            'TRACK_ACTIVATED', tracker.tracks(end), ...
            'minimum_on_duration_reached'); %#ok<AGROW>
    end
end

update = struct( ...
    'tracks', tracker.tracks, ...
    'closedTracks', closedTracks, ...
    'events', events, ...
    'durationSec', durationSec);
end

function [track, events] = updateMatched(track, detection, durationSec, cfg)
events = emptyEvents();
oldState = track.state;
oldFrequency = track.frequencyOffsetHz;
track.frequencyOffsetHz = (1 - cfg.frequencyAlpha) * ...
    track.frequencyOffsetHz + cfg.frequencyAlpha * ...
    detection.frequencyOffsetHz;
track.centerFrequencyHz = detection.centerFrequencyHz + ...
    track.frequencyOffsetHz - detection.frequencyOffsetHz;
track.powerDb = detection.powerDb;
track.noiseFloorDb = detection.noiseFloorDb;
track.snrDb = detection.snrDb;
track.lastSeenWidebandSample = detection.widebandEndSample;
track.lastSeenOutputSample = detection.outputSampleEnd;
track.missingDurationSec = 0;
track.continuousOnSec = track.continuousOnSec + durationSec;
track.hitCount = track.hitCount + uint64(1);
if strcmp(oldState, 'off_pending')
    track.state = 'active';
    events(end+1, 1) = makeEvent( ...
        'TRACK_REACQUIRED', track, 'carrier_returned_within_hang');
elseif strcmp(oldState, 'tentative') && ...
        track.continuousOnSec >= cfg.minOnSec
    track.state = 'active';
    track.isConfirmed = true;
    events(end+1, 1) = makeEvent( ...
        'TRACK_ACTIVATED', track, 'minimum_on_duration_reached');
end
if abs(track.frequencyOffsetHz - oldFrequency) >= ...
        cfg.frequencyEventThresholdHz
    events(end+1, 1) = makeEvent( ...
        'TRACK_FREQUENCY_UPDATED', track, 'smoothed_frequency_update');
end
end

function track = newTrack(id, detection, durationSec)
track = radio.wideband.emptyTrack();
track.trackId = uint64(id);
track.channelId = uint64(id);
track.state = 'tentative';
track.isConfirmed = false;
track.frequencyOffsetHz = detection.frequencyOffsetHz;
track.centerFrequencyHz = detection.centerFrequencyHz;
track.coarseBin = detection.coarseBin;
track.coarseCenterOffsetHz = detection.coarseCenterOffsetHz;
track.powerDb = detection.powerDb;
track.noiseFloorDb = detection.noiseFloorDb;
track.snrDb = detection.snrDb;
track.firstSeenWidebandSample = detection.widebandStartSample;
track.lastSeenWidebandSample = detection.widebandEndSample;
track.firstOutputSample = detection.outputSampleStart;
track.lastSeenOutputSample = detection.outputSampleEnd;
track.continuousOnSec = durationSec;
track.missingDurationSec = 0;
track.hitCount = uint64(1);
track.continuityGeneration = detection.continuityGeneration;
end

function event = makeEvent(type, track, reason)
event = struct( ...
    'type', type, ...
    'trackId', track.trackId, ...
    'state', track.state, ...
    'frequencyOffsetHz', track.frequencyOffsetHz, ...
    'sample', track.lastSeenWidebandSample, ...
    'reason', reason);
end

function events = emptyEvents()
events = struct('type', {}, 'trackId', {}, 'state', {}, ...
    'frequencyOffsetHz', {}, 'sample', {}, 'reason', {});
end
