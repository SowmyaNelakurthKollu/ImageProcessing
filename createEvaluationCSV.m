function createEvaluationCSV(frameFiles,outputFile)

%% =========================================================
% CREATE GROUND TRUTH TEMPLATE
% ==========================================================

numFrames = length(frameFiles);

Frame = strings(numFrames,1);

TargetPresent = false(numFrames,1);

X = nan(numFrames,1);
Y = nan(numFrames,1);
Width = nan(numFrames,1);
Height = nan(numFrames,1);

for k = 1:numFrames

    Frame(k) = string(frameFiles(k).name);

end

groundTruth = table( ...
    Frame, ...
    TargetPresent, ...
    X, ...
    Y, ...
    Width, ...
    Height);

writetable(groundTruth,outputFile);

fprintf('Ground truth template created:\n%s\n', ...
    outputFile);

end