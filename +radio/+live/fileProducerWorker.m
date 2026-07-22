function fileProducerWorker(config, outputQueue, actorId)
%FILEPRODUCERWORKER Pace replay and fan IQ directly to the PSD consumer.
source = [];
ringWriter = [];
try
    source = radio.replay.fileLoopSourceInit(config.path, ...
        'SampleRate', config.sampleRateHz, ...
        'CenterFrequencyHz', config.centerFrequencyHz, ...
        'IqDType', config.iqDType, ...
        'HeaderBytes', config.headerBytes, ...
        'ChunkDurationSec', config.chunkDurationSec, ...
        'ReplayMode', config.replayMode, ...
        'MaxLoops', config.maxLoops, ...
        'EpochSilenceSec', config.epochSilenceSec);
    inputQueue = parallel.pool.PollableDataQueue;
    send(outputQueue, struct('type', 'ready', ...
        'actorId', uint64(actorId), 'inputQueue', inputQueue));

    ringWriter = radio.live.sharedIqRingWriter(config.sharedRing);
    running = false;
    clockToken = [];
    clockBaseSample = uint64(0);
    stepRemaining = uint64(0);
    spectrumQueue = [];
    spectrumActorId = uint64(0);
    spectrumMaxQueueChunks = inf;
    spectrumNeedsDiscontinuity = false;
    spectrumDroppedChunks = uint64(0);

    while true
        command = poll(inputQueue, 0);
        while ~isempty(command)
            if isstruct(command) && isfield(command, 'actorId') && ...
                    command.actorId == actorId
                switch char(command.type)
                    case 'run'
                        running = true;
                        clockToken = tic;
                        clockBaseSample = source.globalNextSample;
                    case 'pause'
                        running = false;
                    case 'step'
                        running = false;
                        stepRemaining = stepRemaining + uint64(command.count);
                    case 'attach_spectrum'
                        spectrumQueue = command.sinkQueue;
                        spectrumActorId = uint64(command.sinkActorId);
                        spectrumMaxQueueChunks = ...
                            double(command.maxQueueChunks);
                    case 'stop'
                        radio.live.sharedIqRingMarkTerminal( ...
                            ringWriter, true);
                        radio.replay.fileLoopSourceClose(source);
                        send(outputQueue, struct('type', 'stopped', ...
                            'actorId', uint64(actorId)));
                        return;
                end
            end
            command = poll(inputQueue, 0);
        end

        if source.terminal
            radio.live.sharedIqRingMarkTerminal(ringWriter, false);
            send(outputQueue, terminalMessage( ...
                source, actorId, spectrumDroppedChunks));
            radio.replay.fileLoopSourceClose(source);
            return;
        end

        dueCount = uint64(0);
        productionLagSec = 0;
        if stepRemaining > 0
            dueCount = stepRemaining;
        elseif running
            elapsed = toc(clockToken);
            targetSample = clockBaseSample + uint64(floor(max(0, ...
                elapsed - config.playoutDelaySec) * config.sampleRateHz));
            if targetSample > source.globalNextSample
                dueSamples = targetSample - source.globalNextSample;
                dueCount = uint64(ceil(double(dueSamples) / ...
                    source.options.chunkSamples));
                productionLagSec = double(dueSamples) / config.sampleRateHz;
            end
        end

        emitted = uint64(0);
        maxBurst = uint64(16);
        while emitted < min(dueCount, maxBurst) && ~source.terminal
            [source, chunk, done, event] = ...
                radio.replay.fileLoopSourceRead(source);
            if isempty(chunk), break; end
            [packedChunk, payload] = ...
                radio.stream.lockedDecoderActorPackChunk(chunk);

            [ringWriter, ~] = radio.live.sharedIqRingWriteTransport( ...
                ringWriter, packedChunk, payload);

            if isempty(spectrumQueue)
                error('radio:live:fileProducerWorker:SpectrumSinkMissing', ...
                    'Replay started before PSD attachment.');
            end
            if spectrumQueue.QueueLength >= spectrumMaxQueueChunks
                spectrumDroppedChunks = ...
                    spectrumDroppedChunks + uint64(1);
                spectrumNeedsDiscontinuity = true;
            else
                if spectrumNeedsDiscontinuity
                    packedChunk.discontinuity = true;
                    spectrumNeedsDiscontinuity = false;
                end
                send(spectrumQueue, struct( ...
                    'type', 'chunk', ...
                    'actorId', spectrumActorId, ...
                    'chunk', packedChunk, ...
                    'payload', payload));
            end
            send(outputQueue, progressMessage( ...
                source, event, actorId, productionLagSec, ...
                spectrumDroppedChunks));
            emitted = emitted + uint64(1);
            if stepRemaining > 0
                stepRemaining = stepRemaining - uint64(1);
            end
            if done, break; end
        end
        if emitted == 0, pause(0.001); end
    end
catch ME
    if ~isempty(ringWriter)
        try
            radio.live.sharedIqRingMarkTerminal(ringWriter, true);
        catch
        end
    end
    if ~isempty(source)
        try
            radio.replay.fileLoopSourceClose(source);
        catch
        end
    end
    send(outputQueue, struct('type', 'error', ...
        'actorId', uint64(actorId), ...
        'errorReason', sprintf('%s: %s', ME.identifier, ME.message)));
end
end

function message = progressMessage( ...
        source, event, actorId, lagSec, spectrumDroppedChunks)
message = struct( ...
    'type', 'progress', ...
    'actorId', uint64(actorId), ...
    'event', event, ...
    'sourceSampleEnd', source.globalNextSample, ...
    'completedLoops', source.completedLoops, ...
    'productionLagSec', lagSec, ...
    'spectrumDroppedChunks', spectrumDroppedChunks);
end

function message = terminalMessage( ...
        source, actorId, spectrumDroppedChunks)
message = struct( ...
    'type', 'terminal', ...
    'actorId', uint64(actorId), ...
    'sourceSampleEnd', source.globalNextSample, ...
    'completedLoops', source.completedLoops, ...
    'productionLagSec', 0, ...
    'spectrumDroppedChunks', spectrumDroppedChunks);
end
