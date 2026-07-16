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

    directSpectrum = logical(fieldOr(config, 'directFanout', false));
    if isfield(config, 'sharedRing') && ~isempty(config.sharedRing)
        ringWriter = radio.live.sharedIqRingWriter(config.sharedRing);
    end
    running = false;
    clockToken = [];
    clockBaseSample = uint64(0);
    stepRemaining = uint64(0);
    maxLagSec = 0;
    terminalSent = false;
    decoderArmed = false;

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
                    case 'arm_decoder'
                        decoderArmed = true;
                    case 'detach_decoder'
                        decoderArmed = false;
                    case 'stop'
                        if ~isempty(ringWriter)
                            ringWriter = radio.live.sharedIqRingMarkTerminal( ...
                                ringWriter, true);
                        end
                        source = radio.replay.fileLoopSourceClose(source);
                        send(outputQueue, struct('type', 'stopped', ...
                            'actorId', uint64(actorId)));
                        return;
                end
            end
            command = poll(inputQueue, 0);
        end

        if source.terminal
            if ~terminalSent
                if ~isempty(ringWriter)
                    ringWriter = radio.live.sharedIqRingMarkTerminal( ...
                        ringWriter, false);
                end
                send(outputQueue, terminalMessage( ...
                    source, actorId, maxLagSec, spectrumDroppedChunks, ...
                    ringSequence(ringWriter)));
                terminalSent = true;
            end
            source = radio.replay.fileLoopSourceClose(source);
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
                maxLagSec = max(maxLagSec, productionLagSec);
            end
        end

        emitted = uint64(0);
        maxBurst = uint64(16);
        while emitted < min(dueCount, maxBurst) && ~source.terminal
            if decoderArmed && ...
                    outputQueue.QueueLength >= config.maxQueueChunks
                error('radio:live:fileProducerWorker:QueueOverrun', ...
                    ['Decode relay exceeded %d chunks; input was stopped ', ...
                     'instead of dropping IQ.'], config.maxQueueChunks);
            end
            [source, chunk, done, event] = ...
                radio.replay.fileLoopSourceRead(source);
            if isempty(chunk), break; end
            [packedChunk, payload] = ...
                radio.stream.lockedDecoderActorPackChunk(chunk);

            if ~isempty(ringWriter)
                [ringWriter, ~] = radio.live.sharedIqRingWriteTransport( ...
                    ringWriter, packedChunk, payload);
            end

            if directSpectrum
                if isempty(spectrumQueue)
                    error('radio:live:fileProducerWorker:SpectrumSinkMissing', ...
                        'Direct replay started before PSD attachment.');
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
            end

            if decoderArmed || ~directSpectrum
                send(outputQueue, chunkMessage( ...
                    source, event, actorId, packedChunk, payload, ...
                    productionLagSec, maxLagSec, spectrumDroppedChunks, ...
                    ringSequence(ringWriter)));
            else
                send(outputQueue, progressMessage( ...
                    source, event, actorId, productionLagSec, ...
                    maxLagSec, spectrumDroppedChunks, ...
                    ringSequence(ringWriter)));
            end
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
            ringWriter = radio.live.sharedIqRingMarkTerminal( ...
                ringWriter, true);
        catch
        end
    end
    if ~isempty(source)
        try, source = radio.replay.fileLoopSourceClose(source); catch, end %#ok<NASGU>
    end
    send(outputQueue, struct('type', 'error', ...
        'actorId', uint64(actorId), ...
        'errorReason', sprintf('%s: %s', ME.identifier, ME.message)));
end
end

function message = chunkMessage(source, event, actorId, chunk, payload, ...
        lagSec, maxLagSec, spectrumDroppedChunks, ringWriteSequence)
message = progressMessage(source, event, actorId, lagSec, maxLagSec, ...
    spectrumDroppedChunks, ringWriteSequence);
message.type = 'chunk';
message.chunk = chunk;
message.payload = payload;
end

function message = progressMessage(source, event, actorId, lagSec, ...
        maxLagSec, spectrumDroppedChunks, ringWriteSequence)
message = struct( ...
    'type', 'progress', ...
    'actorId', uint64(actorId), ...
    'event', event, ...
    'sourceSampleEnd', source.globalNextSample, ...
    'completedLoops', source.completedLoops, ...
    'productionLagSec', lagSec, ...
    'maxProductionLagSec', maxLagSec, ...
    'spectrumDroppedChunks', spectrumDroppedChunks, ...
    'ringWriteSequence', uint64(ringWriteSequence));
end

function message = terminalMessage(source, actorId, maxLagSec, ...
        spectrumDroppedChunks, ringWriteSequence)
message = struct( ...
    'type', 'terminal', ...
    'actorId', uint64(actorId), ...
    'sourceSampleEnd', source.globalNextSample, ...
    'completedLoops', source.completedLoops, ...
    'productionLagSec', 0, ...
    'maxProductionLagSec', maxLagSec, ...
    'spectrumDroppedChunks', spectrumDroppedChunks, ...
    'ringWriteSequence', uint64(ringWriteSequence));
end

function sequence = ringSequence(writer)
sequence = uint64(0);
if ~isempty(writer), sequence = writer.nextSequence - uint64(1); end
end

function value = fieldOr(s, name, fallback)
if isfield(s, name), value = s.(name); else, value = fallback; end
end
