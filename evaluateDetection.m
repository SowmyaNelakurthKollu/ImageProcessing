function metrics = evaluateDetection( ...
    predictions, ...
    groundTruth)

%% =========================================================
% EVALUATE DETECTION
% ==========================================================

TP = 0;
FP = 0;
FN = 0;

correctLocalization = 0;
targetPresentCount = 0;
targetAbsentCount = 0;

numFrames = height(predictions);

for k = 1:numFrames

    %% Ground truth

    gtPresent = groundTruth.TargetPresent(k);

    if gtPresent

        targetPresentCount = ...
            targetPresentCount + 1;

    else

        targetAbsentCount = ...
            targetAbsentCount + 1;

    end

    %% Prediction

    predicted = predictions.Detected(k);

    %% =====================================================
    % Target is present
    % =====================================================

    if gtPresent

        if predicted

            predictedCenter = [
                predictions.CenterX(k), ...
                predictions.CenterY(k)
            ];

            gtBBox = [
                groundTruth.X(k), ...
                groundTruth.Y(k), ...
                groundTruth.Width(k), ...
                groundTruth.Height(k)
            ];

            %% Check localization

            correct = centerInsideBBox( ...
                predictedCenter, ...
                gtBBox);

            if correct

                TP = TP + 1;

                correctLocalization = ...
                    correctLocalization + 1;

            else

                FN = FN + 1;

            end

        else

            FN = FN + 1;

        end

    %% =====================================================
    % Target is absent
    % =====================================================

    else

        if predicted

            FP = FP + 1;

        end

    end

end

%% Metrics

precision = ...
    TP / max(TP + FP,1);

recall = ...
    TP / max(TP + FN,1);

localizationSuccess = ...
    correctLocalization / ...
    max(targetPresentCount,1);

%% Store

metrics.TP = TP;
metrics.FP = FP;
metrics.FN = FN;

metrics.Precision = precision;
metrics.Recall = recall;

metrics.LocalizationSuccess = ...
    localizationSuccess;

metrics.NumFrames = numFrames;

metrics.TargetPresent = ...
    targetPresentCount;

metrics.TargetAbsent = ...
    targetAbsentCount;

end