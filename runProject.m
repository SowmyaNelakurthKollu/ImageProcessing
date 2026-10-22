function summary = runProject(config)
if nargin < 1, config = projectConfig(); end
rng(config.Seed, 'twister');
labels = readtable(config.LabelFile, 'TextType', 'string');
[labels, changedValidation] = rebalanceRequiredSplit(labels, "validation");
[labels, changedEvaluation] = rebalanceRequiredSplit(labels, "evaluation");
if changedValidation || changedEvaluation
    writetable(labels, config.LabelFile);
end
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

[images, features, points, anchorInfo] = setupAnchors(config.AnchorFolder, config);
bodyIdx = anchorInfo.Part == "body";     % color baseline uses body anchors only
bodyMap = find(bodyIdx);                 % baseline index -> global anchor index
if ~any(bodyIdx)
    error('Project:NoBodyAnchors', 'At least one body anchor is required for the baseline.');
end
writetable(anchorInfo, fullfile(config.ResultsFolder,'anchor_info.csv'));

n = height(labels);
baseline = predictionTable(labels.Frame);
final = predictionTable(labels.Frame);
baselineCandidates = cell(n,1);
finalCandidates = cell(n,1);
candidateRecall = false(n,1);
details = cell(n,1);

for k = 1:n
    frame = imread(fullfile(config.LocalDataSave, labels.Frame(k)));
    originalSize = [size(frame,1),size(frame,2)];
    scale = min(1, config.MaxImageSide/max(originalSize));
    frame = imresize(frame, max(1,round(originalSize*scale)));
    ratio = [size(frame,2)/originalSize(2),size(frame,1)/originalSize(1)];

    proposalStart = tic;
    boxes = generateCandidates(frame, config);
    proposalTime = toc(proposalStart);

    timer = tic;
    b = recognizeBaseline(frame, images(bodyIdx), Inf, config, boxes);
    baseline.Seconds(k) = toc(timer) + proposalTime;

    timer = tic;
    f = recognizeTarget(frame, features, points, images, Inf, config, boxes);
    %T = f.candidates(:, {'Candidate','Anchor','Matches','Inliers','InlierRatio', ...
    %         'Coverage','Valid','Reason','Score'});
    % disp(T(1:min(20,height(T)),:))

    final.Seconds(k) = toc(timer) + proposalTime;

    % Map baseline anchor index (body subset) to the global anchor index.
    if b.bestAnchor > 0
        b.bestAnchor = bodyMap(b.bestAnchor);
    end
    if ~isempty(b.candidates)
        b.candidates.Anchor = bodyMap(b.candidates.Anchor);
    end

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
    fprintf('%d/%d [%s]: %d candidates; color %.3f; SIFT %.3f\n', ...
        k,n,labels.Split(k),size(boxes,1),b.score,f.score);
end

validation = labels.Split == "validation";
evaluation = labels.Split == "evaluation";
test       = labels.Split == "test";

summary.Status = 'Measured on reviewed held-out frames';
summary.Created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
summary.MATLABVersion = version;
summary.Toolboxes = ver;
summary.Config = config;
summary.NumAnchors = numel(images);
summary.NumBodyAnchors = sum(bodyIdx);
summary.ValidationFrames = sum(validation);
summary.EvaluationFrames = sum(evaluation);
summary.TestFrames = sum(test);
summary.ValidationTargetPresent = sum(labels.TargetPresent(validation));
summary.ValidationTargetAbsent = sum(~labels.TargetPresent(validation));
summary.TargetPresent = sum(labels.TargetPresent(evaluation));
summary.TargetAbsent = sum(~labels.TargetPresent(evaluation));
summary.TestTargetPresent = sum(labels.TargetPresent(test));
summary.TestTargetAbsent = sum(~labels.TargetPresent(test));

methods = {'Baseline','Final'};
tables = {baseline,final};
thresholds = zeros(1,2);
testScored = false;

for m = 1:2
    predictions = tables{m};

    % Threshold is chosen on validation rows only.
    validationScores = predictions.Score(validation & predictions.Valid);
    validationScores = validationScores(isfinite(validationScores));
    grid = unique([0; validationScores; Inf]);
    validRows = validation & isfinite(predictions.Score) & ismember(predictions.Valid,[0 1]);
    [sweep, threshold, feasible] = tuneThreshold(predictions(validRows,:), ...
        labels(validRows,:), grid, config.PrecisionTarget, config.RecallTarget);
    thresholds(m) = threshold;
    predictions.Detected = predictions.Valid & predictions.Score >= threshold;

    % Evaluation split.
    [metrics,outcomes] = evaluateDetection(predictions(evaluation,:), labels(evaluation,:));
    metrics.Threshold = threshold;
    metrics.ValidationTargetsMet = feasible;
    metrics.EvaluationTargetsMet = metrics.Precision >= config.PrecisionTarget && ...
        metrics.Recall >= config.RecallTarget;
    metrics.MeanSecondsPerFrame = mean(predictions.Seconds(evaluation));
    metrics.AnchorWins = arrayfun(@(a) sum(predictions.BestAnchor(evaluation) == a & ...
        predictions.Valid(evaluation)), 1:numel(images));
    summary.(methods{m}) = metrics;
    writetable(predictions, fullfile(config.ResultsFolder, [lower(methods{m}) '_predictions.csv']));
    writetable(sweep, fullfile(config.ResultsFolder, [lower(methods{m}) '_thresholds.csv']));
    writetable(outcomes, fullfile(config.ResultsFolder, [lower(methods{m}) '_outcomes.csv']));

    % Test split: same threshold, scored once, never used for tuning.
    if any(test)
        if any(labels.TargetPresent(test) == 1) && any(labels.TargetPresent(test) == 0)
            [mt, ot] = evaluateDetection(predictions(test,:), labels(test,:));
            mt.Threshold = threshold;
            mt.MeanSecondsPerFrame = mean(predictions.Seconds(test));
            mt.AnchorWins = arrayfun(@(a) sum(predictions.BestAnchor(test) == a & ...
                predictions.Valid(test)), 1:numel(images));
            summary.([methods{m} 'Test']) = mt;
            writetable(ot, fullfile(config.ResultsFolder, [lower(methods{m}) '_test_outcomes.csv']));
            testScored = true;
        else
            warning('Project:TestUnbalanced', ...
                'Test split lacks present or absent frames; test metrics skipped.');
        end
    end
    tables{m} = predictions;
end

summary.CandidateCenterRecall = sum(candidateRecall(evaluation)) / ...
    max(summary.TargetPresent,1);
summary.CandidateCenterRecallTest = sum(candidateRecall(test)) / ...
    max(summary.TestTargetPresent,1);

writetable(labels, fullfile(config.ResultsFolder,'labels_snapshot.csv'));
writetable(readtable(config.AnchorBoxes), fullfile(config.ResultsFolder,'anchor_boxes_snapshot.csv'));
writeCandidates(baselineCandidates,labels.Frame,fullfile(config.ResultsFolder,'baseline_candidates.csv'));
writeCandidates(finalCandidates,labels.Frame,fullfile(config.ResultsFolder,'final_candidates.csv'));
save(fullfile(config.ResultsFolder,'experiment.mat'), 'config','labels','tables', ...
    'details','baselineCandidates','finalCandidates','thresholds','summary','anchorInfo');

fid = fopen(fullfile(config.ResultsFolder,'summary.json'), 'w');
if fid < 0, error('Project:WriteFailed', 'Cannot write results summary.'); end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(summary, 'PrettyPrint', true));

fprintf('\n--- Evaluation split ---\n');
disp(struct2table([summary.Baseline,summary.Final], 'AsArray',true));
if testScored
    fprintf('--- Test split (scored once, thresholds from validation) ---\n');
    disp(struct2table([summary.BaselineTest,summary.FinalTest], 'AsArray',true));
end
fprintf('Saved measured results. Run exportDemo for annotated detection visualizations.\n');
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
        ~all(ismember(labels.Split, ["validation","evaluation","test"]))
    error('Project:InvalidSplit', ...
        'Frames must be unique with validation/evaluation/test split labels.');
end
% Use the exact evaluation validator before expensive feature extraction.
dummy = predictionTable(labels.Frame);
evaluateDetection(dummy,labels);
% Present and absent frames are required where thresholds are tuned and checked.
for split = ["validation","evaluation"]
    subset = labels.TargetPresent(labels.Split == split);
    if ~any(subset == 1) || ~any(subset == 0)
        error('Project:UnbalancedSplit', '%s must contain present and absent frames.', split);
    end
end
for k = 1:height(labels)
    framePath = fullfile(config.LocalDataSave, labels.Frame(k));
    if ~isfile(framePath)
        error('Project:MissingFrame', 'Missing frame: %s.', framePath);
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



function [labels, wasUpdated] = rebalanceRequiredSplit(labels, targetSplit)
wasUpdated = false;

idx = labels.Split == targetSplit;
if ~any(idx)
    error('Project:UnbalancedSplit', ...
        '%s split is empty. Edit the label file so it contains present and absent frames.', ...
        targetSplit);
end

hasPresent = any(labels.TargetPresent(idx) == 1);
hasAbsent = any(labels.TargetPresent(idx) == 0);

if hasPresent && hasAbsent
    return;
end

if ~hasAbsent
    donorPool = find(labels.Split ~= targetSplit & labels.TargetPresent == 0);
    receiverPool = find(idx & labels.TargetPresent == 1);
elseif ~hasPresent
    donorPool = find(labels.Split ~= targetSplit & labels.TargetPresent == 1);
    receiverPool = find(idx & labels.TargetPresent == 0);
else
    return;
end

if isempty(donorPool) || isempty(receiverPool)
    error('Project:UnbalancedSplit', ...
        'Cannot rebalance %s automatically. Edit the label file so it contains both present and absent frames.', ...
        targetSplit);
end

donor = donorPool(randi(numel(donorPool)));
receiver = receiverPool(randi(numel(receiverPool)));

sourceSplit = labels.Split(donor);
labels.Split(receiver) = sourceSplit;
labels.Split(donor) = targetSplit;
wasUpdated = true;
end
