function [metrics, outcomes] = evaluateDetection(predictions, groundTruth, minIoU)
if nargin < 3 || isempty(minIoU)
    minIoU = 0;
end
requiredP = {'Frame','Detected','CenterX','CenterY'};
requiredG = {'Frame','TargetPresent','X','Y','Width','Height'};
if ~all(ismember(requiredP, predictions.Properties.VariableNames)) || ...
        ~all(ismember(requiredG, groundTruth.Properties.VariableNames))
    error('Project:InvalidSchema', 'Prediction or ground-truth table is missing required columns.');
end
pf = string(predictions.Frame);
gf = string(groundTruth.Frame);
if isempty(pf) || numel(unique(pf)) ~= numel(pf) || numel(unique(gf)) ~= numel(gf)
    error('Project:InvalidFrames', 'Evaluation needs nonempty, unique frame IDs.');
end
[found, order] = ismember(pf, gf);
if height(predictions) ~= height(groundTruth) || ~all(found)
    error('Project:FrameMismatch', 'Prediction and reference frame sets must match exactly.');
end
groundTruth = groundTruth(order,:);
if ismember('Reviewed', groundTruth.Properties.VariableNames) && ...
        ~all(groundTruth.Reviewed == 1)
    error('Project:UnreviewedLabels', 'Every reference label must be reviewed.');
end
if ~all(ismember(groundTruth.TargetPresent, [0,1])) || ...
        ~all(ismember(predictions.Detected, [0,1]))
    error('Project:InvalidLabels', 'Presence and detection flags must be 0 or 1, never unknown.');
end
present = logical(groundTruth.TargetPresent);
accepted = logical(predictions.Detected);
boxes = groundTruth{:, {'X','Y','Width','Height'}};
if any(~isfinite(boxes(present,:)), 'all') || any(boxes(present,3:4) <= 0, 'all')
    error('Project:InvalidBox', 'Present targets need finite positive reference boxes.');
end
centers = predictions{:, {'CenterX','CenterY'}};
if any(~isfinite(centers(accepted,:)), 'all')
    error('Project:InvalidPrediction', 'Accepted predictions need finite centers.');
end
hasBoxes = all(ismember({'X','Y','Width','Height'}, predictions.Properties.VariableNames));
if minIoU > 0 && ~hasBoxes
    error('Project:InvalidSchema', 'IoU evaluation needs predicted X, Y, Width, Height.');
end
localized = false(height(predictions),1);
iou = nan(height(predictions),1);
for k = find(present & accepted)'
    localized(k) = centerInsideBBox(centers(k,:), boxes(k,:));
    if hasBoxes
        iou(k) = bboxIoU(predictions{k, {'X','Y','Width','Height'}}, boxes(k,:));
        localized(k) = localized(k) && iou(k) >= minIoU;
    end
end
tp = present & accepted & localized;
% A mislocalized acceptance is both a false alarm and a missed real target.
fp = accepted & ~tp;
fn = present & ~tp;
tn = ~present & ~accepted;
metrics.TP = sum(tp);
metrics.FP = sum(fp);
metrics.FN = sum(fn);
metrics.TN = sum(tn);
metrics.Precision = sum(tp) / max(sum(accepted),1);
metrics.Recall = sum(tp) / max(sum(present),1);
metrics.CorrectLocalization = sum(tp);
metrics.AcceptedDetections = sum(accepted);
metrics.LocalizationSuccess = sum(tp) / max(sum(accepted),1);
metrics.PrecisionDefined = any(accepted);
metrics.RecallDefined = any(present);
metrics.LocalizationSuccessDefined = any(accepted);
metrics.NumFrames = height(predictions);
metrics.TargetPresent = sum(present);
metrics.TargetAbsent = sum(~present);
metrics.MislocalizedAcceptances = sum(present & accepted & ~localized);
metrics.MinIoU = minIoU;
metrics.MeanIoU = mean(iou(present & accepted), 'omitnan');
outcomes = table(pf, tp, fp, fn, tn, localized, iou, ...
    'VariableNames', {'Frame','TP','FP','FN','TN','Localized','IoU'});
end


function value = bboxIoU(a, b)
if any(~isfinite([a b]))
    value = 0;
    return;
end
w = min(a(1)+a(3), b(1)+b(3)) - max(a(1), b(1));
h = min(a(2)+a(4), b(2)+b(4)) - max(a(2), b(2));
inter = max(w, 0) * max(h, 0);
value = inter / max(a(3)*a(4) + b(3)*b(4) - inter, eps);
end
