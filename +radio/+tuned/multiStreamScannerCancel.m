function [scanner, report] = multiStreamScannerCancel(scanner, varargin)
%MULTISTREAMSCANNERCANCEL Abort all selected carriers without tail flush.
p = inputParser;
p.addParameter('Reason', 'multi_stream_scanner_canceled');
p.parse(varargin{:});
if scanner.finalized
    report = struct('reason', char(p.Results.Reason), ...
        'channelReports', {cell(scanner.channelCount, 1)}, ...
        'taskCount', 0, 'alreadyFinalized', true);
    return;
end

channelReports = cell(scanner.channelCount, 1);
taskCount = 0;
for k = 1:scanner.channelCount
    [scanner.channels{k}, channelReports{k}] = ...
        radio.tuned.streamScannerCancel(scanner.channels{k}, ...
            'Reason', p.Results.Reason);
    taskCount = taskCount + channelReports{k}.taskCount;
end
scanner.finalized = true;
report = struct('reason', char(p.Results.Reason), ...
    'channelReports', {channelReports}, ...
    'taskCount', taskCount, 'alreadyFinalized', false);
end
