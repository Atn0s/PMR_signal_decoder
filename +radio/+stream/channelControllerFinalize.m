function [controller, closedEpoch] = channelControllerFinalize( ...
        controller, endSample, varargin)
%CHANNELCONTROLLERFINALIZE Close any active epoch at end of a finite source.
p = inputParser;
p.addParameter('Reason', 'end_of_input');
p.parse(varargin{:});

endSample = uint64(endSample);
if endSample < controller.lastSampleEnd
    error('radio:stream:channelControllerFinalize:EndSample', ...
        'Final source sample cannot precede the last processed sample.');
end
[controller, closedEpoch] = radio.stream.channelControllerCloseEpoch( ...
    controller, endSample, p.Results.Reason);
controller.state = 'NO_SIGNAL';
controller.activityDetector = radio.stream.activityDetectorInit( ...
    controller.sampleRateHz, 'Config', controller.config.activity);
controller.lastSampleEnd = endSample;
end
