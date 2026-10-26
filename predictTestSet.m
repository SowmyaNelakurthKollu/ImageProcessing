function summary = predictTestSet(testFolder, labelFile, config)
% Run the baseline and the SIFT method on a separate test folder, using the
% thresholds runProject tuned on the validation split (results/experiment.mat).
% labelFile is optional: a CSV with Frame, TargetPresent, X, Y, Width, Height,
% where Frame is a file name or a path ending in the file name.
%   predictTestSet('C:\path\to\test')
%   predictTestSet('C:\path\to\test', 'annotations\test_frames.csv')
if nargin < 3 || isempty(config), config = projectConfig(); end
if nargin < 2, labelFile = ""; end
experimentFile = fullfile(config.ResultsFolder, 'experiment.mat');
if ~isfile(experimentFile)
    error('Project:MissingExperiment', 'Run runProject first; it tunes the thresholds.');
end
if ~isfolder(testFolder)
    error('Project:MissingFolder', 'Test folder not found: %s', testFolder);
end
experiment = load(experimentFile, 'thresholds', 'config');
thresholds = experiment.thresholds;
% Recognize with the same settings the thresholds were tuned with.
settings = experiment.config;
settings.AnchorFolder = config.AnchorFolder;
settings.AnchorBoxes = config.AnchorBoxes;

listing = dir(testFolder);
root = listing(1).folder;
files = dir(fullfile(root, '**', '*'));
files = files(~[files.isdir]);
[~, ~, ext] = cellfun(@fileparts, {files.name}, 'UniformOutput', false);
files = files(ismember(lower(ext), {'.png','.jpg','.jpeg','.bmp','.tif','.tiff'}));
if isempty(files)
    error('Project:NoImages', 'No images found in %s.', root);
end
paths = sort(string(fullfile({files.folder}, {files.name}))');
frames = regexprep(extractAfter(paths, strlength(root)), '^[\\/]+', '');

rng(settings.Seed, 'twister');
[images, features, points] = setupAnchors(settings.AnchorFolder, settings);
n = numel(paths);
tables = {emptyPredictions(frames), emptyPredictions(frames)};
for k = 1:n
    frame = imread(paths(k));
    if size(frame,3) == 1, frame = repmat(frame, [1 1 3]); end
    originalSize = [size(frame,1), size(frame,2)];
    scale = min(1, settings.MaxImageSide/max(originalSize));
    frame = imresize(frame, max(1, round(originalSize*scale)));
    ratio = [size(frame,2)/originalSize(2), size(frame,1)/originalSize(1)];
    timer = tic;
    boxes = generateCandidates(frame, settings);
    proposalTime = toc(timer);
    timer = tic;
    results{1} = recognizeBaseline(frame, images, Inf, settings, boxes); %#ok<AGROW>
    elapsed(1) = toc(timer) + proposalTime;
    timer = tic;
    results{2} = recognizeTarget(frame, features, points, images, Inf, settings, boxes);
    elapsed(2) = toc(timer) + proposalTime;
    for m = 1:2
        tables{m} = storeResult(tables{m}, k, results{m}, ratio, elapsed(m), thresholds(m));
    end
    fprintf('%d/%d %s: %d candidates; color %.3f (accepted=%d); SIFT %.3f (accepted=%d)\n', ...
        k, n, frames(k), size(boxes,1), tables{1}.Score(k), tables{1}.Detected(k), ...
        tables{2}.Score(k), tables{2}.Detected(k));
end

outFolder = fullfile(config.ResultsFolder, 'test');
if ~isfolder(outFolder), mkdir(outFolder); end
methods = {'baseline','final'};
for m = 1:2
    writetable(tables{m}, fullfile(outFolder, [methods{m} '_predictions.csv']));
end

summary.TestFolder = root;
summary.NumFrames = n;
summary.Thresholds = thresholds;
summary.BaselineAccepted = sum(tables{1}.Detected);
summary.FinalAccepted = sum(tables{2}.Detected);

% Optional evaluation against reference labels.
labels = table();
labelled = false(n,1);
outcomes = {[], []};
if strlength(string(labelFile)) > 0
    labels = readtable(labelFile, 'TextType', 'string');
    keys = lower(regexprep(labels.Frame, '^.*[\\/]', ''));
    [labelled, order] = ismember(lower(regexprep(frames, '^.*[\\/]', '')), keys);
    if ~any(labelled)
        error('Project:NoLabelledFrames', 'No test image matches a Frame in %s.', labelFile);
    end
    labels = labels(order(labelled), :);
    labels.Frame = frames(labelled);
    metrics = cell(1,2);
    for m = 1:2
        [metrics{m}, outcomes{m}] = evaluateDetection(tables{m}(labelled,:), labels, config.MinIoU);
        metrics{m}.Threshold = thresholds(m);
        metrics{m}.MeanSecondsPerFrame = mean(tables{m}.Seconds(labelled));
        writetable(outcomes{m}, fullfile(outFolder, [methods{m} '_outcomes.csv']));
    end
    summary.LabelledFrames = sum(labelled);
    summary.Baseline = metrics{1};
    summary.Final = metrics{2};
    disp(struct2table([metrics{1}, metrics{2}], 'AsArray', true));
end

% Annotated images, sorted by outcome when labels exist, else by decision.
visuals = fullfile(outFolder, 'visualizations');
if isfolder(visuals), rmdir(visuals, 's'); end
colors = {'yellow','green'};
names = {'Color baseline','SIFT final'};
labelRow = cumsum(labelled);
for k = 1:n
    image = imread(paths(k));
    if size(image,3) == 1, image = repmat(image, [1 1 3]); end
    if labelled(k) && labels.TargetPresent(labelRow(k))
        image = insertShape(image, 'Rectangle', labels{labelRow(k), {'X','Y','Width','Height'}}, ...
            'Color', 'cyan', 'LineWidth', 3);
    end
    [~, base] = fileparts(paths(k));
    for m = 1:2
        p = tables{m};
        single = image;
        if p.Detected(k)
            single = insertShape(single, 'Rectangle', p{k, {'X','Y','Width','Height'}}, ...
                'Color', colors{m}, 'LineWidth', 3);
        end
        single = insertText(single, [5 5], sprintf('%s: accepted=%d score=%.3f', ...
            names{m}, p.Detected(k), p.Score(k)), 'FontSize', 16, ...
            'BoxColor', 'black', 'TextColor', colors{m});
        if labelled(k)
            folder = outcomeName(outcomes{m}, labelRow(k));
        elseif p.Detected(k)
            folder = "Accepted";
        else
            folder = "Rejected";
        end
        outDir = fullfile(visuals, methods{m}, folder);
        if ~isfolder(outDir), mkdir(outDir); end
        imwrite(single, fullfile(outDir, sprintf('test_%03d_%s.jpg', k, base)));
    end
end
fprintf('Saved test predictions and images in %s.\n', outFolder);
end

function predictions = emptyPredictions(frames)
n = numel(frames);
predictions = table(frames(:), zeros(n,1), false(n,1), false(n,1), zeros(n,1), ...
    nan(n,1), nan(n,1), nan(n,1), nan(n,1), nan(n,1), nan(n,1), zeros(n,1), ...
    'VariableNames', {'Frame','Score','Valid','Detected','BestAnchor', ...
    'X','Y','Width','Height','CenterX','CenterY','Seconds'});
end

function predictions = storeResult(predictions, k, result, ratio, seconds, threshold)
predictions.Score(k) = result.score;
predictions.Valid(k) = result.valid;
predictions.Detected(k) = result.valid && result.score >= threshold;
predictions.BestAnchor(k) = result.bestAnchor;
predictions.Seconds(k) = seconds;
if result.valid
    box = result.bbox;
    box(1:2) = (box(1:2)-0.5)./ratio + 0.5;
    box(3:4) = box(3:4)./ratio;
    predictions{k, {'X','Y','Width','Height'}} = box;
    predictions{k, {'CenterX','CenterY'}} = box(1:2) + box(3:4)/2;
end
end

function name = outcomeName(outcomes, j)
if outcomes.TP(j)
    name = "TruePositives";
elseif outcomes.FP(j)
    name = "FalsePositives";
elseif outcomes.TN(j)
    name = "TrueNegatives";
else
    name = "FalseNegatives";
end
end
