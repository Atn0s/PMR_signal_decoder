function [pool, info] = acquireParallelPool(varargin)
%ACQUIREPARALLELPOOL Reuse or create the persistent protocol-probe pool.
p = inputParser;
p.addParameter('NumWorkers', 5);
p.addParameter('AllowCreate', true);
p.addParameter('PoolType', 'auto');
p.addParameter('CreateAttempts', 2);
p.parse(varargin{:});

info = struct( ...
    'available', false, ...
    'created', false, ...
    'reused', false, ...
    'profile', '', ...
    'poolType', '', ...
    'jobStorageLocation', '', ...
    'numWorkers', 0, ...
    'requestedWorkers', double(p.Results.NumWorkers), ...
    'createAttempts', 0, ...
    'reason', '');
pool = [];
requestedType = lower(char(p.Results.PoolType));
if ~any(strcmp(requestedType, {'auto', 'threads', 'processes'}))
    error('radio:stream:acquireParallelPool:PoolType', ...
        'PoolType must be auto, threads, or processes.');
end
if strcmp(requestedType, 'auto')
    requestedType = 'processes';
end

if exist('parpool', 'file') ~= 2 || exist('parfeval', 'file') ~= 2 || ...
        ~license('test', 'Distrib_Computing_Toolbox')
    info.reason = 'parallel_computing_toolbox_unavailable';
    return;
end

pool = gcp('nocreate');
if ~isempty(pool)
    if isa(pool, 'parallel.ThreadPool')
        existingType = 'threads';
    else
        existingType = 'processes';
    end
    if ~strcmp(existingType, requestedType)
        pool = [];
        info.reason = sprintf('existing_%s_pool_does_not_match_requested_%s_pool', ...
            existingType, requestedType);
        return;
    end
    info.available = true;
    info.reused = true;
    if isa(pool, 'parallel.ThreadPool')
        info.profile = 'threads';
        info.poolType = 'threads';
    else
        info.profile = pool.Cluster.Profile;
        info.poolType = 'processes';
    end
    info.numWorkers = pool.NumWorkers;
    return;
end
if ~p.Results.AllowCreate
    info.reason = 'parallel_pool_not_running';
    return;
end

try
    workerCount = max(1, round(p.Results.NumWorkers));
    if strcmp(requestedType, 'threads')
        info.createAttempts = 1;
        pool = parpool('threads', workerCount);
        info.profile = 'threads';
        info.poolType = 'threads';
    else
        lastError = [];
        for attempt = 1:max(1, round(p.Results.CreateAttempts))
            info.createAttempts = attempt;
            try
                cluster = parcluster('local');
                jobStorageLocation = tempname;
                [created, message] = mkdir(jobStorageLocation);
                if ~created
                    error('radio:stream:acquireParallelPool:JobStorage', ...
                        'Unable to create parallel job storage: %s', message);
                end
                cluster.JobStorageLocation = jobStorageLocation;
                actualWorkers = min(workerCount, cluster.NumWorkers);
                pool = parpool(cluster, actualWorkers);
                info.profile = cluster.Profile;
                info.poolType = 'processes';
                info.jobStorageLocation = jobStorageLocation;
                break;
            catch lastError
                pool = [];
                if attempt < p.Results.CreateAttempts
                    pause(0.25);
                end
            end
        end
        if isempty(pool), rethrow(lastError); end
    end
    info.available = true;
    info.created = true;
    info.numWorkers = pool.NumWorkers;
catch ME
    pool = [];
    info.reason = sprintf('%s: %s', ME.identifier, ME.message);
end
end
