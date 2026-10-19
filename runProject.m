function summary = runProject(config)
if nargin < 1, config = projectConfig(); end
rng(config.Seed, 'twister');
labels = readtable(config.LabelFile, 'TextType', 'string');
validateLabels(labels, config);
if ~isfolder(config.ResultsFolder), mkdir(config.ResultsFolder); end
% Invalidate old success artifacts before starting a new experiment.
generated = ["summary.json","experiment.mat","demonstration.mp4"];
for name = generated
    path = fullfile(config.ResultsFolder,name);
    if isfile(path), delete(path); end
end
visuals = dir(fullfile(config.ResultsFolder,'visualizations','frame_*.jpg'));
for k = 1:numel(visuals)
    delete(fullfile(visuals(k).folder,visuals(k).name));
end
[images, features, points] = setupAnchors(config.AnchorFolder, config);
n = height(labels);
baseline = predictionTable(labels.Frame);
final = predictionTable(labels.Frame);
baselineCandidates = cell(n,1);
finalCandidates = cell(n,1);
candidateRecall = false(n,1);
details = cell(n,1);
for k = 1:n
    frame = imread(fullfile(config.Root, labels.Frame(k)));
    originalSize = [size(frame,1),size(frame,2)];
    scale = min(1, config.MaxImageSide/max(originalSize));
    frame = imresize(frame, max(1,round(originalSize*scale)));
    ratio = [size(frame,2)/originalSize(2),size(frame,1)/originalSize(1)];
    proposalStart = tic;
    boxes = generateCandidates(frame, config);
    proposalTime = toc(proposalStart);
    timer = tic;
    b = recognizeBaseline(frame, images, Inf, config, boxes);
    baseline.Seconds(k) = toc(timer) + proposalTime;
    timer = tic;
    f = recognizeTarget(frame, features, points, images, Inf, config, boxes);
    final.Seconds(k) = toc(timer) + proposalTime;
    baseline = storePrediction(baseline,k,b,ratio);
    final = storePrediction(final,k,f,ratio);
    baselineCandidates{k} = b.candidates;
    finalCandidates{k} = f.candidates;
    if ~isempty(b.candidates)
        baselineCandidates{k}.BBox = unscaleBoxes(b.candidates.BBox, ratio);
    end
    if ~isempty(f.candidates)
        finalCandidates{k}.BBox = unscaleBoxes(f.candidates.BBox, ratio);
    end
    details{k} = f;
    if labels.TargetPresent(k)
        reference = labels{k, {'X','Y','Width','Height'}};
        originalBoxes = unscaleBoxes(boxes, ratio);
        for j = 1:size(originalBoxes,1)
            center = originalBoxes(j,1:2) + originalBoxes(j,3:4)/2;
            candidateRecall(k) = candidateRecall(k) || centerInsideBBox(center,reference);
        end
    end
    fprintf('%d/%d: %d candidates; color %.3f; SIFT %.3f\n', ...
        k,n,size(boxes,1),b.score,f.score);
end
validation = labels.Split == "validation";
evaluation = labels.Split == "evaluation";
summary.Status = 'Measured on reviewed held-out frames';
summary.Created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
summary.MATLABVersion = version;
summary.Toolboxes = ver;
summary.Config = config;
summary.ValidationFrames = sum(validation);
summary.EvaluationFrames = sum(evaluation);
summary.ValidationTargetPresent = sum(labels.TargetPresent(validation));
summary.ValidationTargetAbsent = sum(~labels.TargetPresent(validation));
summary.TargetPresent = sum(labels.TargetPresent(evaluation));
summary.TargetAbsent = sum(~labels.TargetPresent(evaluation));
methods = {'Baseline','Final'};
tables = {baseline,final};
thresholds = zeros(1,2);
for m = 1:2
    predictions = tables{m};
    validationScores = predictions.Score(validation & predictions.Valid);
    grid = unique([0; validationScores; Inf]);
    [sweep, threshold, feasible] = tuneThreshold(predictions(validation,:), ...
        labels(validation,:), grid, config.PrecisionTarget, config.RecallTarget);
    thresholds(m) = threshold;
    predictions.Detected = predictions.Valid & predictions.Score >= threshold;
    [metrics,outcomes] = evaluateDetection(predictions(evaluation,:), labels(evaluation,:));
    metrics.Threshold = threshold;
    metrics.ValidationTargetsMet = feasible;
    metrics.EvaluationTargetsMet = metrics.Precision >= config.PrecisionTarget && ...
        metrics.Recall >= config.RecallTarget;
    metrics.MeanSecondsPerFrame = mean(predictions.Seconds(evaluation));
    metrics.AnchorWins = arrayfun(@(a) sum(predictions.BestAnchor(evaluation) == a & ...
        predictions.Valid(evaluation)), 1:3);
    summary.(methods{m}) = metrics;
    writetable(predictions, fullfile(config.ResultsFolder, [lower(methods{m}) '_predictions.csv']));
    writetable(sweep, fullfile(config.ResultsFolder, [lower(methods{m}) '_thresholds.csv']));
    writetable(outcomes, fullfile(config.ResultsFolder, [lower(methods{m}) '_outcomes.csv']));
    tables{m} = predictions;
end
summary.CandidateCenterRecall = sum(candidateRecall(evaluation)) / ...
    max(summary.TargetPresent,1);
writetable(labels, fullfile(config.ResultsFolder,'labels_snapshot.csv'));
writetable(readtable(config.AnchorBoxes), fullfile(config.ResultsFolder,'anchor_boxes_snapshot.csv'));
writeCandidates(baselineCandidates,labels.Frame,fullfile(config.ResultsFolder,'baseline_candidates.csv'));
writeCandidates(finalCandidates,labels.Frame,fullfile(config.ResultsFolder,'final_candidates.csv'));
save(fullfile(config.ResultsFolder,'experiment.mat'), 'config','labels','tables', ...
    'details','baselineCandidates','finalCandidates','thresholds','summary');
fid = fopen(fullfile(config.ResultsFolder,'summary.json'), 'w');
if fid < 0, error('Project:WriteFailed', 'Cannot write results summary.'); end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(summary, 'PrettyPrint', true));
disp(struct2table([summary.Baseline,summary.Final], 'AsArray',true));
fprintf('Saved measured results. Next: exportDemo; then run the report builder.\n');
end

function validateLabels(labels, config)
required = {'Frame','Split','TargetPresent','X','Y','Width','Height','Reviewed','Distractor'};
if ~all(ismember(required, labels.Properties.VariableNames)) || isempty(labels)
    error('Project:InvalidSchema', 'Run prepareAnnotations to create the label schema.');
end
if ~all(labels.Reviewed == 1)
    error('Project:UnreviewedLabels', 'Run labelProject; %d frames remain unreviewed.', ...
        sum(labels.Reviewed ~= 1));
end
if numel(unique(labels.Frame)) ~= height(labels) || ...
        ~all(ismember(labels.Split, ["validation","evaluation"]))
    error('Project:InvalidSplit', 'Frames must be unique with validation/evaluation split labels.');
end
% Use the exact evaluation validator before expensive feature extraction.
dummy = predictionTable(labels.Frame);
evaluateDetection(dummy,labels);
for split = ["validation","evaluation"]
    subset = labels.TargetPresent(labels.Split == split);
    if ~any(subset == 1) || ~any(subset == 0)
        error('Project:UnbalancedSplit', '%s must contain present and absent frames.', split);
    end
end
for k = 1:height(labels)
    if ~isfile(fullfile(config.Root, labels.Frame(k)))
        error('Project:MissingFrame', 'Missing frame: %s.', labels.Frame(k));
    end
end
end

function predictions = predictionTable(frames)
n = numel(frames);
predictions = table(string(frames),zeros(n,1),false(n,1),false(n,1), ...
    zeros(n,1),nan(n,1),nan(n,1),nan(n,1),nan(n,1),nan(n,1),nan(n,1), ...
    zeros(n,1), 'VariableNames', {'Frame','Score','Valid','Detected','BestAnchor', ...
    'X','Y','Width','Height','CenterX','CenterY','Seconds'});
end

function predictions = storePrediction(predictions,k,result,ratio)
predictions.Score(k) = result.score;
predictions.Valid(k) = result.valid;
predictions.BestAnchor(k) = result.bestAnchor;
if result.valid
    box = unscaleBoxes(result.bbox,ratio);
    predictions{k, {'X','Y','Width','Height'}} = box;
    predictions{k, {'CenterX','CenterY'}} = box(1:2)+box(3:4)/2;
end
end

function boxes = unscaleBoxes(boxes,ratio)
boxes(:,1:2) = (boxes(:,1:2)-0.5)./ratio + 0.5;
boxes(:,3:4) = boxes(:,3:4)./ratio;
end

function writeCandidates(candidates,frames,path)
combined = table();
for k = 1:numel(candidates)
    rows = candidates{k};
    if isempty(rows), continue; end
    rows = addvars(rows,repmat(frames(k),height(rows),1), ...
        (1:height(rows))','Before',1,'NewVariableNames',{'Frame','Rank'});
    combined = [combined; rows]; %#ok<AGROW>
end
if isempty(combined)
    combined = table(strings(0,1),zeros(0,1),zeros(0,1), ...
        'VariableNames',{'Frame','Rank','Score'});
end
writetable(combined,path);
end
