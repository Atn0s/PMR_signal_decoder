function state = ddcRetarget(state, frequencyOffsetHz, varargin)
%DDCRETARGET Reuse a prewarmed external-mixer DDC for another carrier.
p = inputParser;
p.addParameter('InputCenterFrequencyHz', state.inputCenterFrequencyHz);
p.addParameter('TargetCenterFrequencyHz', []);
p.addParameter('ChannelId', state.channelId);
p.parse(varargin{:});

if ~isfield(state, 'mixerMode') || ~strcmp(state.mixerMode, 'external')
    error('radio:tuned:ddcRetarget:MixerMode', ...
        'Only an external-mixer DDC can be retargeted without recompilation.');
end
validateattributes(frequencyOffsetHz, {'numeric'}, ...
    {'scalar', 'real', 'finite'});
if abs(frequencyOffsetHz) + state.config.stopbandFrequencyHz >= ...
        state.inputSampleRateHz / 2
    error('radio:tuned:ddcRetarget:FrequencyOutsideInput', ...
        ['The requested channel plus its anti-alias transition band must ', ...
        'remain inside the captured Nyquist band.']);
end
inputCenterFrequencyHz = double(p.Results.InputCenterFrequencyHz);
targetCenterFrequencyHz = p.Results.TargetCenterFrequencyHz;
if isempty(targetCenterFrequencyHz)
    targetCenterFrequencyHz = inputCenterFrequencyHz + frequencyOffsetHz;
end

try, reset(state.converter); catch, end
state.frequencyOffsetHz = double(frequencyOffsetHz);
state.inputCenterFrequencyHz = inputCenterFrequencyHz;
state.targetCenterFrequencyHz = double(targetCenterFrequencyHz);
state.channelId = p.Results.ChannelId;
state.mixerStep = exp(-1i * 2 * pi * double(frequencyOffsetHz) / ...
    state.inputSampleRateHz);
state.mixerPhase = complex(1);
state.pendingIq = complex(zeros(0, 1));
state.pendingSourceSampleStart = uint64(0);
state.expectedInputSample = [];
state.nextOutputSample = uint64(0);
state.nextSequenceNumber = uint64(0);
state.continuityGeneration = uint64(0);
state.inputSamplesReceived = uint64(0);
state.inputSamplesConverted = uint64(0);
state.outputSamplesProduced = uint64(0);
end
