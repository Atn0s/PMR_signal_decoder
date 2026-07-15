function state = multiDdcRetarget(state, frequencyOffsetsHz, varargin)
%MULTIDDCRETARGET Reuse a prewarmed matrix DDC for a selected carrier set.
p = inputParser;
p.addParameter('InputCenterFrequencyHz', state.inputCenterFrequencyHz);
p.parse(varargin{:});
frequencyOffsetsHz = double(frequencyOffsetsHz(:));
if isempty(frequencyOffsetsHz) || numel(frequencyOffsetsHz) > state.capacity
    error('radio:tuned:multiDdcRetarget:Count', ...
        'Offset count must be between one and the prepared capacity.');
end
if ~isempty(state.expectedInputSample)
    error('radio:tuned:multiDdcRetarget:Started', ...
        'A matrix DDC cannot be retargeted after input begins.');
end
if any(abs(frequencyOffsetsHz) + state.config.stopbandFrequencyHz >= ...
        state.inputSampleRateHz / 2)
    error('radio:tuned:multiDdcRetarget:FrequencyOutsideInput', ...
        'Every selected channel must remain inside the input Nyquist band.');
end
offsets = zeros(state.capacity, 1);
offsets(1:numel(frequencyOffsetsHz)) = frequencyOffsetsHz;
state.activeChannelCount = numel(frequencyOffsetsHz);
state.frequencyOffsetsHz = offsets;
state.mixerSteps = exp(-1i .* 2 .* pi .* offsets.' ./ ...
    state.inputSampleRateHz);
state.mixerBlockSteps = state.mixerSteps .^ state.inputBlockSamples;
phase = (-1i .* 2 .* pi ./ state.inputSampleRateHz) .* ...
    (0:state.inputBlockSamples-1).' .* offsets.';
state.mixerTemplate = exp(phase);
state.mixerPhases = complex(ones(1, state.capacity));
state.inputCenterFrequencyHz = double(p.Results.InputCenterFrequencyHz);
state.targetCenterFrequenciesHz = ...
    state.inputCenterFrequencyHz + offsets;
reset(state.converter);
end
