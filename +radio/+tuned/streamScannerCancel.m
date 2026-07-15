function [scanner, report] = streamScannerCancel(scanner, varargin)
%STREAMSCANNERCANCEL Abort one tuned scanner without flushing more IQ.
p = inputParser;
p.addParameter('Reason', 'stream_scanner_canceled');
p.parse(varargin{:});
if scanner.finalized
    report = struct('reason', char(p.Results.Reason), ...
        'taskCount', 0, 'alreadyFinalized', true);
    return;
end

[scanner.coordinator, coordinatorReport] = ...
    radio.stream.raceCoordinatorCancel(scanner.coordinator, ...
        'Reason', p.Results.Reason);
try
    release(scanner.ddc.converter);
catch
end
scanner.finalized = true;
report = struct('reason', char(p.Results.Reason), ...
    'taskCount', coordinatorReport.taskCount, ...
    'alreadyFinalized', false, ...
    'coordinator', coordinatorReport);
end
