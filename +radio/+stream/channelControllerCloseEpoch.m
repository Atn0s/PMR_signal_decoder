function [controller, closedEpoch] = channelControllerCloseEpoch( ...
        controller, endSample, reason)
%CHANNELCONTROLLERCLOSEEPOCH Close the active RF epoch at an absolute sample.
closedEpoch = [];
if isempty(controller.currentEpoch)
    return;
end

endSample = uint64(endSample);
if endSample < controller.currentEpoch.candidateStartSample
    error('radio:stream:channelControllerCloseEpoch:EndBeforeStart', ...
        'Epoch end cannot precede its candidate start.');
end
controller.currentEpoch.endSample = endSample;
controller.currentEpoch.state = 'CLOSED';
controller.currentEpoch.status = 'closed';
controller.currentEpoch.closeReason = char(reason);
closedEpoch = controller.currentEpoch;
controller.lastClosedEpoch = closedEpoch;
controller.currentEpoch = [];
controller.generation = controller.generation + uint64(1);
end
