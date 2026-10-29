function [thresholdResults, selectedThreshold, feasible] = tuneThreshold(predictions, groundTruth, thresholds, precisionTarget, recallTarget)
if nargin < 4, precisionTarget = 0.75; end
if nargin < 5, recallTarget = 0.60; end
if ~istable(predictions)
    error('Project:LocalizationRequired', ...
        'Pass predictions with Score, Valid, Frame and centers, not just presence scores.');
end
if ~all(ismember({'Score','Valid'}, predictions.Properties.VariableNames)) || ...
        any(~isfinite(predictions.Score)) || ~all(ismember(predictions.Valid,[0,1]))
    error('Project:InvalidScores', 'Finite Score and binary Valid columns are required.');
end
if ~any(groundTruth.TargetPresent == 1) || ~any(groundTruth.TargetPresent == 0)
    error('Project:UnbalancedValidation', 'Validation needs real targets AND target-absent negatives.');
end
thresholds = unique(thresholds(:));
if isempty(thresholds) || any(isnan(thresholds)) || any(thresholds < 0)
    error('Project:InvalidThresholds', 'Provide nonnegative thresholds (Inf permits reject-all).');
end
precision = zeros(size(thresholds));
recall = precision;
tp = precision; fp = precision; fn = precision;
for k = 1:numel(thresholds)
    predictions.Detected = predictions.Valid & predictions.Score >= thresholds(k);
    metrics = evaluateDetection(predictions, groundTruth);
    precision(k) = metrics.Precision;
    recall(k) = metrics.Recall;
    tp(k) = metrics.TP; fp(k) = metrics.FP; fn(k) = metrics.FN;
end
f1 = 2*precision.*recall ./ max(precision+recall, eps);
thresholdResults = table(thresholds,precision,recall,tp,fp,fn,f1, ...
    'VariableNames', {'Threshold','Precision','Recall','TP','FP','FN','F1'});
eligible = find(precision >= precisionTarget & recall >= recallTarget);
feasible = ~isempty(eligible);
if ~feasible
    warning('Project:TargetsNotMet', ...
        'No validation threshold meets both targets; choosing best F1 without claiming success.');
    eligible = (1:numel(thresholds))';
end
rank = sortrows([f1(eligible),precision(eligible),thresholds(eligible),eligible], [-1,-2,-3]);
selectedThreshold = thresholds(rank(1,4));
end
