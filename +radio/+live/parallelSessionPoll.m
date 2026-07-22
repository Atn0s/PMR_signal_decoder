function [session, update] = parallelSessionPoll(session)
%PARALLELSESSIONPOLL Advance the client coordinator without blocking input.
update = emptyUpdate();
if isempty(session) || session.closed || strcmp(session.mode, 'COMPLETED')
    return;
end
token = tic;
runtime = session.config.runtime;

[session.actors.producer, producerEvents] = ...
    radio.live.fileProducerPoll(session.actors.producer, ...
        'MaxEvents', runtime.maxEventsPerPoll);
[session, update] = handleProducerEvents(session, update, producerEvents);
[session, update] = pollDdc(session, update);

[maxChunks, budgetSec] = drainAllowance(session);
[session, update] = drainResults( ...
    session, update, maxChunks, budgetSec);

[session.actors.spectrum, latestSpectrum] = ...
    radio.live.spectrumActorPoll(session.actors.spectrum);
if session.actors.spectrum.failed
    error('radio:live:parallelSessionPoll:Spectrum', ...
        '%s', session.actors.spectrum.errorReason);
end
if ~isempty(latestSpectrum)
    session.spectrum = latestSpectrum;
    update.spectrum = latestSpectrum;
end

session = updateMetrics(session, toc(token));
session = updateMode(session);
if session.producerTerminal && readyToFinalize(session)
    [session, finalUpdate] = ...
        radio.live.parallelSessionFinalize(session);
    update = mergeUpdates(update, finalUpdate);
end
end

function [session, update] = handleProducerEvents(session, update, events)
for eventIndex = 1:numel(events)
    event = events{eventIndex};
    switch char(event.type)
        case 'progress'
            session.source.globalNextSample = ...
                uint64(event.sourceSampleEnd);
            session.source.completedLoops = ...
                uint64(event.completedLoops);
            if event.event.loopEnded
                update.messages{end+1, 1} = sprintf( ...
                    'Replay loop %d completed.', ...
                    event.event.completedLoops);
            end
        case 'terminal'
            session.producerTerminal = true;
            session.source.terminal = true;
            session.source.globalNextSample = ...
                uint64(event.sourceSampleEnd);
            session.source.completedLoops = ...
                uint64(event.completedLoops);
        case 'error'
            error('radio:live:parallelSessionPoll:Producer', ...
                '%s', event.errorReason);
    end
end
end

function [session, update] = pollDdc(session, update)
if isempty(session.actors.ddc), return; end
[session.actors.ddc, events] = radio.live.ddcActorPoll( ...
    session.actors.ddc, ...
    'MaxEvents', session.config.runtime.maxEventsPerPoll);
for eventIndex = 1:numel(events)
    event = events{eventIndex};
    switch char(event.type)
        case {'baseband','flushed'}
            session.decode.resultQueue{end+1, 1} = event;
            count = uint64(radio.getField( ...
                event.widebandDescriptor, ...
                'transportSampleCount', uint64(0)));
            session.decode.resultSamples = ...
                session.decode.resultSamples + count;
        case 'error'
            error('radio:live:parallelSessionPoll:Ddc', ...
                '%s', event.errorReason);
    end
end
if session.actors.ddc.failed
    error('radio:live:parallelSessionPoll:Ddc', ...
        '%s', session.actors.ddc.errorReason);
end
end

function [maxChunks, budgetSec] = drainAllowance(session)
runtime = session.config.runtime;
maxChunks = runtime.drainChunksPerPoll;
budgetSec = runtime.drainBudgetSec;
readySec = double(session.decode.resultSamples) / ...
    session.metadata.sampleRateHz;
if readySec <= runtime.inputChunkDurationSec, return; end
readyChunks = ceil(readySec / runtime.inputChunkDurationSec);
maxChunks = min(runtime.maxEventsPerPoll, ...
    max(maxChunks, readyChunks));
budgetSec = max(budgetSec, min( ...
    runtime.drainMaxBudgetSec, readySec));
end

function [session, update] = drainResults( ...
        session, update, maxChunks, budgetSec)
scanner = session.decode.scanner;
if isempty(scanner) || scanner.finalized || resultQueueEmpty(session)
    return;
end
token = tic;
processed = 0;
while ~resultQueueEmpty(session) && processed < maxChunks
    if processed > 0 && toc(token) >= budgetSec, break; end
    event = session.decode.resultQueue{session.decode.resultHead};
    session.decode.resultQueue{session.decode.resultHead} = [];
    session.decode.resultHead = session.decode.resultHead + 1;
    count = uint64(radio.getField(event.widebandDescriptor, ...
        'transportSampleCount', uint64(0)));
    session.decode.resultSamples = session.decode.resultSamples - ...
        min(session.decode.resultSamples, count);
    [session.decode.scanner, output] = ...
        radio.tuned.multiStreamScannerFeedBasebands( ...
            session.decode.scanner, event.widebandDescriptor, ...
            event.basebandChunks, 'DdcElapsedSec', event.computeSec);
    if ~isempty(output.newPdus)
        session.pdus = session.decode.scanner.pdus;
        update.newPdus = radio.appendPdus( ...
            update.newPdus, output.newPdus);
    end
    update.messages = appendStateMessages( ...
        update.messages, output, session.decode.offsetsHz);
    processed = processed + 1;
end
session = compactResultQueue(session);
end

function messages = appendStateMessages(messages, output, offsetsHz)
for channelIndex = 1:numel(output.channelOutputs)
    item = output.channelOutputs{channelIndex};
    coordinator = item.coordinator;
    if isempty(coordinator), continue; end
    if isfield(coordinator, 'channel') && ~isempty(coordinator.channel)
        events = coordinator.channel.events;
        for eventIndex = 1:numel(events)
            if strcmp(events(eventIndex).toState, 'CLASSIFYING')
                messages{end+1, 1} = sprintf( ...
                    'SIGNAL_ON ch%d %+.3f kHz epoch %d', ...
                    channelIndex, offsetsHz(channelIndex) / 1e3, ...
                    coordinator.epochId); %#ok<AGROW>
            end
        end
    end
    for eventIndex = 1:numel(coordinator.events)
        event = coordinator.events(eventIndex);
        if any(strcmp(event.type, ...
                {'PROTOCOL_CONFIRMED','PROTOCOL_SWITCH_CONFIRMED'}))
            messages{end+1, 1} = sprintf( ...
                'LOCK ch%d %s epoch %d', channelIndex, ...
                event.protocol, coordinator.epochId); %#ok<AGROW>
        end
    end
end
end

function session = updateMetrics(session, coordinatorSec)
producerLagSec = session.actors.producer.productionLagSec;
ddcInputSec = 0;
if ~isempty(session.actors.ddc)
    ddcInputSec = double(session.actors.ddc.pendingInputSamples) / ...
        session.metadata.sampleRateHz;
end
ddcResultSec = double(session.decode.resultSamples) / ...
    session.metadata.sampleRateHz;
pipelineSec = ddcInputSec + ddcResultSec;
metrics = session.metrics;
metrics.inputLagSec = max(producerLagSec, pipelineSec);
metrics.maxInputLagSec = max( ...
    metrics.maxInputLagSec, metrics.inputLagSec);
metrics.maxProducerLagSec = max( ...
    metrics.maxProducerLagSec, producerLagSec);
metrics.maxDdcInputQueueSec = max( ...
    metrics.maxDdcInputQueueSec, ddcInputSec);
metrics.maxDdcResultQueueSec = max( ...
    metrics.maxDdcResultQueueSec, ddcResultSec);
metrics.maxDecoderPipelineQueueSec = max( ...
    metrics.maxDecoderPipelineQueueSec, pipelineSec);
metrics.coordinatorCount = metrics.coordinatorCount + uint64(1);
metrics.coordinatorTotalSec = ...
    metrics.coordinatorTotalSec + coordinatorSec;
metrics.coordinatorMaxSec = max( ...
    metrics.coordinatorMaxSec, coordinatorSec);
session.metrics = metrics;
end

function session = updateMode(session)
scanner = session.decode.scanner;
if isempty(scanner) || scanner.finalized, return; end
states = cell(scanner.channelCount, 1);
for channelIndex = 1:scanner.channelCount
    states{channelIndex} = ...
        scanner.channels{channelIndex}.coordinator.state;
end
if any(strcmp(states, 'ERROR'))
    error('radio:live:parallelSessionPoll:Scanner', ...
        'One or more carrier scanners entered ERROR.');
elseif all(strcmp(states, 'LOCKED'))
    session.mode = 'LOCKED';
else
    session.mode = 'RUNNING';
end
end

function tf = readyToFinalize(session)
if isempty(session.decode.scanner)
    tf = true;
    return;
end
tf = session.actors.ddc.flushed && ...
    session.actors.ddc.pendingInputSamples == 0 && ...
    resultQueueEmpty(session);
end

function tf = resultQueueEmpty(session)
tf = session.decode.resultHead > ...
    numel(session.decode.resultQueue);
end

function session = compactResultQueue(session)
if resultQueueEmpty(session)
    session.decode.resultQueue = cell(0, 1);
    session.decode.resultHead = 1;
elseif session.decode.resultHead > 64 && ...
        session.decode.resultHead > ...
        numel(session.decode.resultQueue) / 2
    session.decode.resultQueue = session.decode.resultQueue( ...
        session.decode.resultHead:end);
    session.decode.resultHead = 1;
end
end

function update = emptyUpdate()
update = struct('messages', {cell(0, 1)}, ...
    'spectrum', [], 'newPdus', struct([]), 'completed', false);
end

function merged = mergeUpdates(a, b)
merged = a;
merged.messages = [a.messages; b.messages];
if ~isempty(b.spectrum), merged.spectrum = b.spectrum; end
merged.newPdus = radio.appendPdus(a.newPdus, b.newPdus);
merged.completed = a.completed || b.completed;
end
