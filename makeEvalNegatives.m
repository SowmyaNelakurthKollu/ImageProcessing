function labels = makeEvalNegatives(config)
% The eval sequence has no target-absent frames. For each labelled eval frame,
% save the side of the image that excludes the target box (plus a margin) and
% contains the most red, so look-alike objects stay in view, and add it to the
% labels as a reviewed target-absent frame in the same split as its source.
% Rows from sequences outside config.LabelSequences are dropped (backed up).
% Re-running regenerates the crops and replaces earlier negative rows.
if nargin < 1, config = projectConfig(); end
labels = readtable(config.LabelFile, 'TextType', 'string');
if ~all(labels.Reviewed == 1)
    error('Project:UnreviewedLabels', 'Finish labelProject before making negatives.');
end
normalized = replace(labels.Frame, "/", "\");
isNegative = startsWith(normalized, replace(string(config.NegativeFolder), "/", "\"));
keep = false(height(labels),1);
for sequence = string(config.LabelSequences)
    keep = keep | startsWith(normalized, "raw\" + sequence + "\");
end
dropped = ~keep & ~isNegative;
if any(dropped)
    backup = replace(config.LabelFile, '.csv', '_before_eval_only.csv');
    if ~isfile(backup), copyfile(config.LabelFile, backup); end
    fprintf('Dropping %d frames outside %s (backup: %s).\n', sum(dropped), ...
        strjoin(string(config.LabelSequences), ', '), backup);
end
sources = labels(keep,:);

outDir = fullfile(config.LocalDataSave, config.NegativeFolder);
if isfolder(outDir), rmdir(outDir, 's'); end
mkdir(outDir);
negatives = sources([],:);
for k = find(sources.TargetPresent == 1)'
    image = imread(fullfile(config.LocalDataSave, sources.Frame(k)));
    box = sources{k, {'X','Y','Width','Height'}};
    width = size(image,2);
    margin = config.NegativeMargin * box(3);
    leftEnd = floor(box(1) - margin) - 1;
    rightStart = ceil(box(1) + box(3) + margin) + 1;
    sides = zeros(0,2);
    if leftEnd >= config.NegativeMinWidth
        sides(end+1,:) = [1, leftEnd]; %#ok<AGROW>
    end
    if width - rightStart + 1 >= config.NegativeMinWidth
        sides(end+1,:) = [rightStart, width]; %#ok<AGROW>
    end
    if isempty(sides)
        fprintf('Skipping %s: no room beside the target.\n', sources.Frame(k));
        continue;
    end
    red = zeros(size(sides,1),1);
    for j = 1:size(sides,1)
        red(j) = nnz(redMask(image(:, sides(j,1):sides(j,2), :)));
    end
    [~, j] = max(red + 1e-6*(sides(:,2) - sides(:,1)));   % most red, then wider
    [~, name] = fileparts(sources.Frame(k));
    frame = fullfile(string(config.NegativeFolder), name + "_negative.png");
    imwrite(image(:, sides(j,1):sides(j,2), :), fullfile(config.LocalDataSave, frame));
    row = sources(k,:);
    row.Frame = frame;
    row.TargetPresent = 0;
    row{1, {'X','Y','Width','Height'}} = nan(1,4);
    row.Distractor = "Cropped negative (target excluded)";
    negatives = [negatives; row]; %#ok<AGROW>
end
labels = [sources; negatives];
writetable(labels, config.LabelFile);
for split = ["validation","evaluation"]
    inSplit = labels.Split == split;
    fprintf('%s: %d target-present, %d target-absent (cropped).\n', split, ...
        sum(inSplit & labels.TargetPresent == 1), sum(inSplit & labels.TargetPresent == 0));
end
end

function mask = redMask(image)
hsv = rgb2hsv(image);
mask = (hsv(:,:,1) < 0.065 | hsv(:,:,1) > 0.94) & hsv(:,:,2) > 0.45 & hsv(:,:,3) > 0.12;
end
