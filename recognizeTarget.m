function result = recognizeTarget(frame, anchorFeatures, anchorValidPoints, anchorImages, threshold, config, boxes)
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
for c = 1:size(boxes,1)
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
        if row.Matches >= config.MinInliers
            ap = anchorValidPoints{a}(pairs(:,1)).Location;
            fp = validPoints(pairs(:,2)).Location;
            % The status output reports expected RANSAC failures without hiding errors.
            [transform, inliers, status] = estimateGeometricTransform2D( ...
                ap, fp, 'projective', 'MaxNumTrials', 2000, ...
                'Confidence', 99, 'MaxDistance', config.MaxReprojectionError);
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
                row.BBox = predictedBox;
                row.Valid = geometryOK && row.Inliers >= config.MinInliers && ...
                    row.InlierRatio >= config.MinInlierRatio && ...
                    row.Coverage >= config.MinAnchorCoverage;

                failureReason = "geometric/support check failed";
                if ~geometryOK
                    failureReason = "invalid projection";
                elseif row.Inliers < config.MinInliers
                    failureReason = "too few inliers";
                elseif row.InlierRatio < config.MinInlierRatio
                    failureReason = "low inlier ratio";
                elseif row.Coverage < config.MinAnchorCoverage
                    failureReason = "low coverage";
                end

                row.Reason = reason;
                if row.Valid
                    row.Reason = "valid";
                    if result.valid
                        result.score = bestValidScore;
                    elseif isfinite(bestAnyScore)
                        result.score = bestAnyScore;
                    else
                        result.score = 0;
                    end
                    if ~result.valid || row.Score > result.score
                        result.valid = true;
                        result.score = row.Score;
                        result.bestAnchor = a;
                        result.numMatches = row.Matches;
                        result.numInliers = row.Inliers;
                        result.inlierRatio = row.InlierRatio;
                        result.bbox = predictedBox;
                        result.center = predictedBox(1:2) + predictedBox(3:4)/2;
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