function result = recognizeTarget(frame, anchorFeatures, anchorValidPoints, anchorImages, threshold)

if size(frame,3) == 3
    frameGray = rgb2gray(frame);
else
    frameGray = frame;
end

framePoints = detectSIFTFeatures(frameGray);
[frameFeatures, frameValidPoints] = extractFeatures(frameGray, framePoints);

numAnchors = length(anchorFeatures);

scores = zeros(1, numAnchors);
numMatchesAll = zeros(1, numAnchors);
numInliers = zeros(1, numAnchors);
inlierRatios = zeros(1, numAnchors);
tforms = cell(1, numAnchors);

for i = 1:numAnchors

    indexPairs = matchFeatures( ...
        anchorFeatures{i}, ...
        frameFeatures, ...
        'Unique', true, ...
        'MaxRatio', 0.7);

    numMatchesAll(i) = size(indexPairs, 1);

    if numMatchesAll(i) < 4
        continue;
    end

    matchedAnchorPoints = anchorValidPoints{i}(indexPairs(:,1));
    matchedFramePoints = frameValidPoints(indexPairs(:,2));

    try
        [tforms{i}, inlierIdx] = estimateGeometricTransform2D( ...
            matchedAnchorPoints.Location, ...
            matchedFramePoints.Location, ...
            'projective', ...
            'MaxNumTrials', 2000, ...
            'Confidence', 99);

        numInliers(i) = sum(inlierIdx);
        inlierRatios(i) = numInliers(i) / numMatchesAll(i);
        scores(i) = numInliers(i) * inlierRatios(i);

    catch
        scores(i) = 0;
    end
end

[bestScore, bestAnchor] = max(scores);

result.targetPresent = bestScore >= threshold;
result.bestAnchor = bestAnchor;
result.score = bestScore;
result.numMatches = numMatchesAll(bestAnchor);
result.numInliers = numInliers(bestAnchor);
result.inlierRatio = inlierRatios(bestAnchor);
result.bbox = [];
result.center = [];

if result.targetPresent && ~isempty(tforms{bestAnchor})

    [h, w, ~] = size(anchorImages{bestAnchor});

    corners = [
        1 1
        w 1
        w h
        1 h
        ];

    frameCorners = transformPointsForward(tforms{bestAnchor}, corners);

    xMin = min(frameCorners(:,1));
    xMax = max(frameCorners(:,1));
    yMin = min(frameCorners(:,2));
    yMax = max(frameCorners(:,2));

    result.bbox = [xMin yMin xMax - xMin yMax - yMin];
    result.center = [xMin + (xMax - xMin)/2, yMin + (yMax - yMin)/2];
end

end