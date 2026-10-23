function [thresholdResults, bestThreshold, feasible] = tuneThreshold( ...
    scores, groundTruthPresent, thresholds, precisionTarget, recallTarget)
%TUNETHRESHOLD Sweep thresholds and pick the best one.
%
%   [THRESHOLDRESULTS, BESTTHRESHOLD, FEASIBLE] = TUNETHRESHOLD(...)
%   accepts either tables or numeric/logical vectors.

scoreValues = extractVector(scores, "Score");
groundTruthPresent = logical(extractVector(groundTruthPresent, "TargetPresent"));

scoreValues = scoreValues(:);
groundTruthPresent = groundTruthPresent(:);

if numel(scoreValues) ~= numel(groundTruthPresent)
    error('Project:InputSizeMismatch', ...
        'scores and groundTruthPresent must have the same number of elements.');
end

if nargin < 3 || isempty(thresholds)
    thresholds = unique(scoreValues);
end

thresholds = thresholds(:);
nThresholds = numel(thresholds);

thresholdResults = table( ...
    thresholds, zeros(nThresholds,1), zeros(nThresholds,1), ...
    zeros(nThresholds,1), zeros(nThresholds,1), zeros(nThresholds,1), ...
    false(nThresholds,1), ...
    'VariableNames', {'Threshold','Precision','Recall','TP','FP','FN','Feasible'});

for t = 1:nThresholds
    threshold = thresholds(t);

    predicted = scoreValues >= threshold;

    TP = sum(predicted & groundTruthPresent);
    FP = sum(predicted & ~groundTruthPresent);
    FN = sum(~predicted & groundTruthPresent);

    precision = TP / max(TP + FP, 1);
    recall = TP / max(TP + FN, 1);

    thresholdResults.Precision(t) = precision;
    thresholdResults.Recall(t) = recall;
    thresholdResults.TP(t) = TP;
    thresholdResults.FP(t) = FP;
    thresholdResults.FN(t) = FN;
    thresholdResults.Feasible(t) = precision >= precisionTarget && recall >= recallTarget;
end

feasibleRows = thresholdResults.Feasible;

if any(feasibleRows)
    feasible = true;
    candidates = thresholdResults(feasibleRows, :);
    candidates = sortrows(candidates, {'Recall','Precision','Threshold'}, {'descend','descend','ascend'});
    bestThreshold = candidates.Threshold(1);
else
    feasible = false;
    precision = thresholdResults.Precision;
    recall = thresholdResults.Recall;
    f1 = 2 * precision .* recall ./ max(precision + recall, eps);

    candidates = table(f1, thresholdResults.Precision, thresholdResults.Threshold, ...
        'VariableNames', {'F1','Precision','Threshold'});
    candidates = sortrows(candidates, {'F1','Precision','Threshold'}, {'descend','descend','ascend'});
    bestThreshold = candidates.Threshold(1);
end

end

function values = extractVector(inputValue, preferredName)
if istable(inputValue)
    if ismember(preferredName, inputValue.Properties.VariableNames)
        values = inputValue.(preferredName);
    else
        values = inputValue{:,1};
    end
else
    values = inputValue;
end
values = values(:);
end
