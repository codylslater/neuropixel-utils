function rezFull = runKilosort3(imec, paths, exp_template, varargin)

    p = inputParser();
    p.addParameter('saveDir', imec.pathRoot, @ischar);
    p.addParameter('workingDir', tempdir, @ischar); % should be on fast SSD
    p.KeepUnmatched = true;
    p.parse(varargin{:});

    if exist('writeNPY', 'file') ~= 2
        error('npy-matlab was not found on path');
    end

    ops = defaultConfig();
    ops.fproc   = fullfile(p.Results.workingDir, 'temp_wh.dat'); % proc file on a fast SSD
    ops.chanMap = getenv('KILOSORT_CONFIG_FILE');

    % main parameter changes from Kilosort2 to v2.5
    ops.sig        = 20;  % spatial smoothness constant for registration
    ops.fshigh     = 300; % high-pass more aggresively
    ops.nblocks    = 5; % blocks for registration. 0 turns it off, 1 does rigid registration. Replaces "datashift" option. 

    % main parameter changes from Kilosort2.5 to v3.0
    ops.Th       = [9 9];


    ops.fig = true; % default avoid plotting in main loop, can be overriden as parameter to runkilosort3
    ops.save_fig_path = fullfile(paths.raw_neuropixel_data,"plot-drifts",exp_template);
    ops.trange = [0 Inf];

    % custom params added locally
    ops.markSplitsOnly = false; % custom parameter for local working version of kilosort3
    ops.spikeThreshBothDirs = false; % apply spkTh threshold from above and below

    ops.fproc = fullfile(p.Results.workingDir, sprintf('temp_wh_%s.dat', imec.fileStem));

    flds = fieldnames(p.Unmatched);
    for iF = 1:numel(flds)
        fld = flds{iF};
        if isfield(ops, fld)
            ops.(fld) = p.Unmatched.(fld);
        else
            error('Unknown option %s', fld);
        end
    end
    assert(ops.spkTh < 0, 'Option spkTh should be negative');

    ops.root = imec.pathRoot;
    ops.fs = imec.fsAP;        % sampling rate		(omit if already in chanMap file)
    ops.fbinary = imec.pathAP;
    ops.scaleToUv = imec.apScaleToUv;
    if ~exist(ops.fbinary, 'file')
        error('Imec data file not found.');
    end

    ops.saveDir = p.Results.saveDir;
    if ~exist(ops.saveDir, 'dir')
        mkdir(ops.saveDir);
    end

    % build channel map for kilosort, providing coordinates only for good channels
    goodChannels = imec.goodChannels;
    assert(~isempty(goodChannels), 'Must mark good channels');

    map = imec.channelMap;
    chanMap = map.channelIdsMapped;
    xcoords = map.xcoords;
    ycoords = map.ycoords;
    % this is a mask over mapped channels that is true if channel is good
    connected = ismember(1:imec.nChannelsMapped, goodChannels);
    kcoords = map.shankInd;
    ops.chanMap = fullfile(ops.root,'chanMap.mat');
    ops.Nchan = nnz(connected);
    ops.NchanTOT  = imec.nChannels;           % total number of channels (omit if already in chanMap file)

    fs = imec.fsAP;
    save(ops.chanMap, 'chanMap', 'xcoords', 'ycoords', 'connected', 'kcoords', 'fs');

    fprintf('kilosort3: preprocessing\n');
    rez = preprocessDataSub(ops);

    % time-reordering as a function of drift
    rez                = datashift2(rez, 1);

    % main optimization
    [rez, st3, tF]     = extract_spikes(rez);
    rez                = template_learning(rez, tF, st3);
    [rez, st3, tF]     = trackAndSort(rez);
    rez                = final_clustering(rez, tF, st3);
    rez                = find_merges(rez, 1);

    % write to Phy
    fprintf('kilosort3: Saving results for Phy\n')
    rezToPhy(rez, ops.saveDir);

    fprintf('kilosort3: Saving rez to rez.mat\n')
    Neuropixel.exportRezToMat(rez, ops.saveDir);

%     % mark templates that maybe should be split
%     fprintf('Marking split candidates')
%     rez = markSplitCandidates(rez);
%
%     % merge templates that should be merged into new clusters
%     rez = mergeTemplatesIntoClusters(rez);
%
%     % mark split candidates and merged clusters as "mua"
%     rez = assignClusterGroups(rez);

    % remove temporary file
    delete(ops.fproc);
end

function ops = defaultConfig() %#ok<STOUT>
    configFile = getenv('KILOSORT_CONFIG_FILE');
    if isempty(configFile)
        configFile = 'configFile384';
    end
    if ~exist(configFile, 'file')
        error('Could not find kilosort3 config file %s', configFile);
    end

    % treat either as full path or as m file on the path
    run(configFile);

    assert(exist('ops', 'var') > 0, 'Config file %s did not produce ops variable', configFile);
end
