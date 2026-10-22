function labels = prepareAnnotations(config)
if nargin < 1
    config = projectConfig();
end
if isfile(config.LabelFile)
    error('Project:ExistingLabels', ...
        'Labels already exist at %s. Use labelProject to resume.', config.LabelFile);
end
Frame = strings(0,1);
Split = strings(0,1);
for sequence = ["eval", "test"]
    folder = fullfile(config.RawFolder, sequence, 'camera_color_image_raw');
    files = dir(fullfile(folder, '*.png'));
    if isempty(files)
        error('Project:MissingFrames', 'No RGB PNG frames in %s.', folder);
    end
    [~, order] = sort({files.name});
    files = files(order);
    n = numel(files);
    index = (1:n)';
    block = floor((index - 1) / config.SplitBlockLength);
    offset = mod(index - 1, config.SplitBlockLength);

    if sequence == "test"
        % Held-out test sequence: no tuning, so no block split or guard gaps needed.
        eligible = index;
    else
        % Keep a temporal gap on both sides of each validation/evaluation boundary.
        keep = (block == 0 | offset >= config.SplitGuardFrames) & ...
            (index + config.SplitGuardFrames > n | ...
            offset < config.SplitBlockLength - config.SplitGuardFrames);
        eligible = index(keep);
    end

    selected = eligible(unique(round(linspace(1, numel(eligible), ...
        min(config.MaxFramesPerSequence, numel(eligible))))));

    for k = selected'
        Frame(end+1,1) = string(fullfile('raw', sequence, ...
            'camera_color_image_raw', files(k).name)); %#ok<AGROW>
        if sequence == "test"
            Split(end+1,1) = "test"; %#ok<AGROW>
        elseif mod(block(k), 2) == 0
            Split(end+1,1) = "validation"; %#ok<AGROW>
        else
            Split(end+1,1) = "evaluation"; %#ok<AGROW>
        end
    end
end
n = numel(Frame);
labels = table(Frame, Split, nan(n,1), nan(n,1), nan(n,1), nan(n,1), ...
    nan(n,1), false(n,1), repmat("unreviewed",n,1), ...
    'VariableNames', {'Frame','Split','TargetPresent','X','Y','Width', ...
    'Height','Reviewed','Distractor'});
folder = fileparts(config.LabelFile);
if ~isfolder(folder), mkdir(folder); end
writetable(labels, config.LabelFile);
fprintf('Prepared %d unreviewed frames at %s.\n', n, config.LabelFile);
fprintf('Split counts: validation %d, evaluation %d, test %d.\n', ...
    sum(Split=="validation"), sum(Split=="evaluation"), sum(Split=="test"));
fprintf('Run labelProject to label them; NaN is NOT target-absent.\n');
end