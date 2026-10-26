function result = recognizeTarget(frame, anchorFeatures, anchorValidPoints, anchorImages, threshold, config, boxes)
if nargin < 6, config = projectConfig(); end
if nargin < 7, boxes = generateCandidates(frame, config); end
rows = struct('Candidate', {}, 'Anchor', {}, 'Score', {}, 'Matches', {}, ...
    'Inliers', {}, 'InlierRatio', {}, 'Coverage', {}, 'Valid', {}, ...
    'Reason', {}, 'BBox', {});

bestAnyScore = -Inf;
bestValidScore = -Inf;
bestMatches = 0;
matchCandidate = 0;
matchAnchor = 0;
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
result.siftBox = [];
transformType = getOption(config, 'TransformType', 'projective');
for c = 1:size(boxes,1)
    colorBox = redObjectBox(frame, boxes(c,:), config);
    crop = imcrop(frame, boxes(c,:));
    cropScale = config.CandidateSide / max(size(crop,1),size(crop,2));
    cropSize = [size(crop,1),size(crop,2)];
    resizedSize = max(1,round(cropSize*cropScale));
    cropRatio = [resizedSize(2)/cropSize(2),resizedSize(1)/cropSize(1)];
    crop = imresize(crop, resizedSize);
    points = detectSIFTFeatures(im2gray(crop));
    features = [];
    validPoints = points;
    if points.Count >= config.MinInliers
        [features, validPoints] = extractFeatures(im2gray(crop), points);
    end
    for a = 1:numel(anchorImages)
        row = struct('Candidate', c, 'Anchor', a, 'Score', 0, 'Matches', 0, ...
            'Inliers', 0, 'InlierRatio', 0, 'Coverage', 0, 'Valid', false, ...
            'Reason', "insufficient matches", 'BBox', nan(1,4));
        pairs = zeros(0,2);
        if validPoints.Count >= config.MinInliers
            pairs = matchFeatures(anchorFeatures{a}, features, ...
                'Unique', true, 'MaxRatio', config.MatchRatio);
        end
        row.Matches = size(pairs,1);
        if row.Matches > bestMatches
            bestMatches = row.Matches;
            matchCandidate = c;
            matchAnchor = a;
        end
        if row.Matches >= config.MinInliers
            ap = anchorValidPoints{a}(pairs(:,1)).Location;
            fp = validPoints(pairs(:,2)).Location;
            % The status output reports expected RANSAC failures without hiding errors.
            [transform, inliers, status] = estimateGeometricTransform2D( ...
                ap, fp, transformType, 'MaxNumTrials', 2000, ...
                'Confidence', 99, 'MaxDistance', config.MaxReprojectionError * cropScale);
            row.Reason = "RANSAC failed";
            if status == 0
                row.Inliers = sum(inliers);
                row.InlierRatio = row.Inliers / row.Matches;
                locations = ap(inliers,:);
                [h,w,~] = size(anchorImages{a});
                span = max(locations,[],1) - min(locations,[],1);
                row.Coverage = prod(span) / (w*h);

                row.Score = row.Inliers * row.InlierRatio * sqrt(row.Coverage);
                bestAnyScore = max(bestAnyScore, row.Score);


                corners = [1,1; w,1; w,h; 1,h];
                projected = transformPointsForward(transform, corners);
                projected = (projected - 0.5) ./ cropRatio + 0.5 + boxes(c,1:2) - 1;

                [geometryOK, predictedBox, reason] = validProjection(projected, frame, boxes(c,:));
                if geometryOK
                    [geometryOK, reason] = plausibleTransform(transform, predictedBox, colorBox, config);
                end
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

                row.Reason = failureReason;
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
                        result.siftBox = predictedBox;
                        result.bbox = localizationBox(boxes(c,:), colorBox, predictedBox, config);
                        result.center = result.bbox(1:2) + result.bbox(3:4)/2;
                        result.polygon = projected;
                        result.anchorMatchPoints = ap(inliers,:);
                        result.frameMatchPoints = (fp(inliers,:)-0.5)./cropRatio + ...
                            0.5 + boxes(c,1:2) - 1;
                    end
                end
            end
        end
        rows(end+1) = row; %#ok<AGROW>
    end
end
if isempty(rows)
    result.candidates = table();
else
    result.candidates = sortrows(struct2table(rows), {'Valid','Score'}, {'descend','descend'});
end

% Keep the best rejected score for logging; targetPresent still requires valid.
if ~result.valid && isfinite(bestAnyScore)
    result.score = bestAnyScore;
end
% At 640x400 the target gets too few consistent matches for a geometric fit,
% but the number of descriptor matches still separates target from distractors.
if strcmp(getOption(config, 'Verification', 'geometry'), 'matches')
    result.valid = bestMatches > 0 && bestMatches >= getOption(config, 'MinMatches', 1);
    result.score = bestMatches;
    result.numMatches = bestMatches;
    result.bestAnchor = 0;
    result.bbox = [];
    result.center = [];
    if result.valid
        proposal = boxes(matchCandidate,:);
        result.bestAnchor = matchAnchor;
        result.bbox = localizationBox(proposal, redObjectBox(frame, proposal, config), [], config);
        result.center = result.bbox(1:2) + result.bbox(3:4)/2;
    end
end
result.targetPresent = result.valid && result.score >= threshold;
end


function [valid, box, reason] = validProjection(polygon, image, proposal)
box = nan(1,4);
valid = false;
reason = "invalid";

if size(polygon,1) ~= 4 || size(polygon,2) ~= 2 || any(~isfinite(polygon), 'all')
    reason = "bad polygon";
    return;
end

% Reject duplicate or nearly duplicate vertices.
minEdge = inf;
for i = 1:3
    for j = i+1:4
        minEdge = min(minEdge, norm(polygon(i,:) - polygon(j,:)));
    end
end
if minEdge < 1e-3
    reason = "duplicate points";
    return;
end

% Require all 4 points to lie on the convex hull.
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

frameBox = [1, 1, size(image,2), size(image,1)];
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
end


function value = getOption(config, name, default)
value = default;
if isfield(config, name) && ~isempty(config.(name))
    value = config.(name);
end
end


function [ok, reason] = plausibleTransform(transform, predictedBox, colorBox, config)
% With only a handful of matches RANSAC can fit a near-exact but degenerate
% transform (thin sliver or collapsed box); reject those.
ok = false;
L = transform.T(1:2, 1:2);
sx = norm(L(1,:));
sy = norm(L(2,:));
if ~all(isfinite(L), 'all') || det(L) <= 0
    reason = "degenerate/reflected transform";
    return;
end
if max(sx, sy) / max(min(sx, sy), eps) > getOption(config, 'MaxAnisotropy', Inf)
    reason = "anisotropic scale";
    return;
end
if abs(dot(L(1,:), L(2,:))) / (sx * sy) > getOption(config, 'MaxShear', Inf)
    reason = "sheared transform";
    return;
end
if abs(atan2d(L(1,2), L(1,1))) > getOption(config, 'MaxRotationDeg', 180)
    reason = "rotated transform";
    return;
end
maxRatio = getOption(config, 'MaxSizeRatio', Inf);
if ~isempty(colorBox) && isfinite(maxRatio)
    sizeRatio = predictedBox(4) / colorBox(4);
    if sizeRatio > maxRatio || sizeRatio < 1 / maxRatio
        reason = "size inconsistent with red object";
        return;
    end
end
ok = true;
reason = "valid";
end


function box = redObjectBox(frame, proposal, config)
% Tight box around the red cylinder inside the proposal, extended upward
% for the valve. Same color rule as generateCandidates.
box = [];
x1 = max(1, floor(proposal(1)));
y1 = max(1, floor(proposal(2)));
x2 = min(size(frame,2), ceil(proposal(1) + proposal(3)));
y2 = min(size(frame,1), ceil(proposal(2) + proposal(4)));
if x2 <= x1 || y2 <= y1
    return;
end
hsv = rgb2hsv(frame(y1:y2, x1:x2, :));
mask = (hsv(:,:,1) < 0.065 | hsv(:,:,1) > 0.94) & ...
    hsv(:,:,2) > 0.45 & hsv(:,:,3) > 0.12;
mask = imclose(mask, strel('disk', 2, 0));
mask = bwareaopen(mask, config.MinimumRedPixels);
stats = regionprops(mask, 'BoundingBox', 'Area');
if isempty(stats)
    return;
end
[~, idx] = max([stats.Area]);
b = stats(idx).BoundingBox;
headroom = getOption(config, 'ColorBoxHeadroom', 0) * b(4);
top = max(0.5, b(2) + y1 - 1 - headroom);
bottom = b(2) + y1 - 1 + b(4);
box = [b(1) + x1 - 1, top, b(3), bottom - top];
end


function box = localizationBox(proposal, colorBox, siftBox, config)
default = 'sift';
if getOption(config, 'UseColorBox', false)
    default = 'red';
end
switch getOption(config, 'LocalizationBox', default)
    case 'proposal'
        box = proposal;
    case 'red'
        box = colorBox;
    otherwise
        box = siftBox;
end
if isempty(box)
    box = proposal;
end
end
