function state = resetMaxHold(state)
%RESETMAXHOLD Reset Max Hold to the current averaged spectrum.
if state.hasEstimate
    state.maxHoldPsd = state.averagePsd;
else
    state.maxHoldPsd(:) = 0;
end
end
