<<<<<<< Updated upstream
function result = recognizeTarget(frame, anchorFeatures, anchorValidPoints, anchorImages, threshold, config, boxes)
if nargin < 5 || isempty(threshold), threshold = Inf; end
if nargin < 6, config = projectConfig(); end
if nargin < 7, boxes = generateCandidates(frame, config); end

rows = struct('Candidate', {}, 'Anchor', {}, 'Score', {}, 'Matches', {}, ...
    'Inliers', {}, 'InlierRatio', {}, 'Coverage', {}, 'Valid', {}, ...
    'Reason', {}, 'BBox', {});

bestAnyScore = -Inf;
bestValidScore = -Inf;

result.score = 0;
result.bestAnchor = 0;
result.numMatches = 0;
result.numInliers = 0;
result.inlierRatio = 0;
result.bbox = [];
result.center = [];
result.polygon = [];
result.anchorMatchPoints = [];
result.frameMatchPoints = [];
result.valid = false;
result.proposalBox = [];

if isfield(config, 'CandidateScale') && ~isempty(config.CandidateScale)
    candidateScale = config.CandidateScale;
else
    candidateScale = 1;
end

for c = 1:size(boxes, 1)
    crop = imcrop(frame, boxes(c, :));
    if isempty(crop)
        continue;
    end

    cropGray = im2gray(crop);
    cropScale = (config.CandidateSide * candidateScale) / max(size(cropGray, 1), size(cropGray, 2));
    cropSize = [size(cropGray, 1), size(cropGray, 2)];
    resizedSize = max(1, round(cropSize * cropScale));
    cropRatio = [resizedSize(2) / cropSize(2), resizedSize(1) / cropSize(1)];
    cropGray = imresize(cropGray, resizedSize);

    detectArgs = {'ContrastThreshold', config.ContrastThreshold};
    if isfield(config, 'EdgeThreshold') && ~isempty(config.EdgeThreshold)
        detectArgs = [detectArgs, {'EdgeThreshold', config.EdgeThreshold}];
    end

    points = detectSIFTFeatures(cropGray, detectArgs{:});
    features = [];
    validPoints = points;

    if points.Count >= config.MinAnchorPoints
        [features, validPoints] = extractFeatures(cropGray, points);
    end

    for a = 1:numel(anchorImages)
        row = struct('Candidate', c, 'Anchor', a, 'Score', 0, 'Matches', 0, ...
            'Inliers', 0, 'InlierRatio', 0, 'Coverage', 0, 'Valid', false, ...
            'Reason', "too few SIFT points", 'BBox', nan(1, 4));

        pairs = zeros(0, 2);
        if validPoints.Count >= config.MinAnchorPoints && ~isempty(anchorFeatures{a})
            pairs = matchFeatures(anchorFeatures{a}, features, ...
                'Unique', true, 'MaxRatio', config.MatchRatio);
        end

        row.Matches = size(pairs, 1);

        if row.Matches < config.MinInliers
            row.Reason = "insufficient matches";
            rows(end + 1) = row; %#ok<AGROW>
            continue;
        end

        ap = anchorValidPoints{a}(pairs(:, 1)).Location;
        fp = validPoints(pairs(:, 2)).Location;

        [transform, inliers, status] = estimateGeometricTransform2D( ...
            ap, fp, 'affine', 'MaxNumTrials', 5000, ...
            'Confidence', 99, 'MaxDistance', config.MaxReprojectionError);

        if status ~= 0 || ~any(inliers)
            row.Reason = "RANSAC failed";
            rows(end + 1) = row; %#ok<AGROW>
            continue;
        end

        row.Inliers = sum(inliers);
        row.InlierRatio = row.Inliers / row.Matches;

        locations = ap(inliers, :);
        [h, w, ~] = size(anchorImages{a});
        span = max(locations, [], 1) - min(locations, [], 1);
        row.Coverage = prod(span) / (w * h);

        row.Score = row.Inliers * row.InlierRatio * sqrt(max(row.Coverage, eps));
        bestAnyScore = max(bestAnyScore, row.Score);

        corners = [1, 1; w, 1; w, h; 1, h];
        projected = transformPointsForward(transform, corners);
        projected = (projected - 0.5) ./ cropRatio + 0.5 + boxes(c, 1:2) - 1;

        [geometryOK, predictedBox, reason] = validProjectionnew(projected, frame, boxes(c, :));
        row.BBox = predictedBox;

        row.Valid = geometryOK && row.Inliers >= config.MinInliers && ...
            row.InlierRatio >= config.MinInlierRatio && ...
            row.Coverage >= config.MinAnchorCoverage;

        failureReason = "geometric/support check failed";
        if ~geometryOK
            failureReason = reason;
        elseif row.Inliers < config.MinInliers
            failureReason = "too few inliers";
        elseif row.InlierRatio < config.MinInlierRatio
            failureReason = "low inlier ratio";
        elseif row.Coverage < config.MinAnchorCoverage
            failureReason = "low coverage";
        end

        if row.Valid
            row.Reason = "valid";
            if row.Score > bestValidScore
                bestValidScore = row.Score;
                result.valid = true;
                result.score = row.Score;
                result.bestAnchor = a;
                result.numMatches = row.Matches;
                result.numInliers = row.Inliers;
                result.inlierRatio = row.InlierRatio;
                result.bbox = predictedBox;
                result.center = predictedBox(1:2) + predictedBox(3:4) / 2;
                result.polygon = projected;
                result.anchorMatchPoints = ap(inliers, :);
                result.frameMatchPoints = (fp(inliers, :) - 0.5) ./ cropRatio + 0.5 + boxes(c, 1:2) - 1;
                result.proposalBox = boxes(c, :);
            end
        else
            row.Reason = failureReason;
        end

        rows(end + 1) = row; %#ok<AGROW>
    end
end

if isempty(rows)
    result.candidates = table();
else
    result.candidates = sortrows(struct2table(rows), {'Valid','Score'}, {'descend','descend'});
end

result.targetPresent = result.valid && result.score >= threshold;
end




function [valid, box, reason] = validProjectionnew(polygon, image, proposal)
box = nan(1, 4);
valid = false;
reason = "invalid";

if size(polygon, 1) ~= 4 || size(polygon, 2) ~= 2 || any(~isfinite(polygon), 'all')
    reason = "bad polygon";
    return;
end

low = min(polygon, [], 1);
high = max(polygon, [], 1);
box = [low, high - low];

if any(box(3:4) < 6)
    reason = "too small";
    return;
end

if any(low < [0.5, 0.5]) || any(high > [size(image, 2) + 0.5, size(image, 1) + 0.5])
    reason = "out of bounds";
    return;
end

% Optional soft check: comment this out if it is still too strict.
proposalCenter = proposal(1:2) + proposal(3:4) / 2;
boxCenter = low + box(3:4) / 2;
maxShift = 0.75 * max(proposal(3:4));
if norm(boxCenter - proposalCenter) > maxShift
    reason = "center outside proposal";
    return;
end

valid = true;
reason = "valid";
end


function [valid, box, reason] = validProjection(polygon, image, proposal)
box = nan(1, 4);
valid = false;
reason = "invalid";

if size(polygon, 1) ~= 4 || size(polygon, 2) ~= 2 || any(~isfinite(polygon), 'all')
    reason = "bad polygon";
    return;
end

minEdge = inf;
for i = 1:3
    for j = i + 1:4
        minEdge = min(minEdge, norm(polygon(i,:) - polygon(j,:)));
    end
end
if minEdge < 1e-3
    reason = "duplicate points";
    return;
end

polygon = double(polygon);
hullIdx = convhull(polygon(:,1), polygon(:,2));
if numel(hullIdx) ~= 5
    reason = "non-convex";
    return;
end
polygon = polygon(hullIdx(1:4), :);

low = min(polygon, [], 1);
high = max(polygon, [], 1);
box = [low, high - low];
center = low + box(3:4) / 2;

frameBox = [1, 1, size(image, 2), size(image, 1)];
area = polyarea(polygon(:,1), polygon(:,2));

if any(box(3:4) <= 4)
    reason = "too small";
elseif area <= 25
    reason = "area too small";
elseif area / prod(box(3:4)) <= 0.05
    reason = "low fill ratio";
elseif area >= 4 * prod(proposal(3:4))
    reason = "too large";
elseif ~centerInsideBBox(center, proposal)
    reason = "center outside proposal";
elseif ~centerInsideBBox(center, frameBox)
    reason = "center outside frame";
elseif any(low < [1, 1]) || any(high > [size(image,2), size(image,1)])
    reason = "out of bounds";
else
    valid = true;
    reason = "valid";
end
=======
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
>>>>>>> Stashed changes
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