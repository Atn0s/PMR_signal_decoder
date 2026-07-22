function parallelFrontendRenderRuntime(view, snapshot, sampleRateHz, wallSec, hint)
%PARALLELFRONTENDRENDERRUNTIME Render the compact runtime diagnostics.
logicalSec = double(snapshot.sourceNextSample) / sampleRateHz;
view.logicalTime.Text = sprintf('%.3f s', logicalSec);
view.inputLag.Text = sprintf('%.0f ms (max %.0f)', ...
    1e3 * snapshot.inputLagSec, 1e3 * snapshot.maxInputLagSec);
if logicalSec > 0
    view.rtf.Text = sprintf('%.3f', wallSec / logicalSec);
end
view.pduCount.Text = sprintf('%d', numel(snapshot.pdus));
if isempty(snapshot.scanner)
    view.winners.Text = '-';
else
    winners = snapshot.scanner.selectedProtocols;
    winners(cellfun(@isempty, winners)) = {'-'};
    view.winners.Text = strjoin(winners, ' | ');
end
if snapshot.decoderPipelineQueueSec > 0
    view.hint.Text = sprintf('Decoder backlog: %.3f s.', ...
        snapshot.decoderPipelineQueueSec);
else
    view.hint.Text = hint;
end
end
