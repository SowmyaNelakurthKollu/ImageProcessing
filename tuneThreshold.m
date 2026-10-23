function thresholdResults = tuneThreshold( ...
    scores, ...
    groundTruthPresent, ...
    thresholds)

%% =========================================================
% THRESHOLD TUNING
% ==========================================================

thresholdResults = table();

thresholdResults.Threshold = thresholds(:);

thresholdResults.Precision = ...
    zeros(length(thresholds),1);

thresholdResults.Recall = ...
    zeros(length(thresholds),1);

thresholdResults.TP = ...
    zeros(length(thresholds),1);

thresholdResults.FP = ...
    zeros(length(thresholds),1);

thresholdResults.FN = ...
    zeros(length(thresholds),1);

for t = 1:length(thresholds)

    threshold = thresholds(t);

    predicted = scores >= threshold;

    TP = sum(predicted & groundTruthPresent);

    FP = sum(predicted & ~groundTruthPresent);

    FN = sum(~predicted & groundTruthPresent);

    precision = ...
        TP / max(TP+FP,1);

    recall = ...
        TP / max(TP+FN,1);

    thresholdResults.Precision(t) = ...
        precision;

    thresholdResults.Recall(t) = ...
        recall;

    thresholdResults.TP(t) = TP;
    thresholdResults.FP(t) = FP;
    thresholdResults.FN(t) = FN;

end

end