function result = recognizeTarget(frame, anchorFeatures, anchorValidPoints, anchorImages, threshold, config, boxes)
if nargin < 6, config = projectConfig(); end
if nargin < 7, boxes = generateCandidates(frame, config); end
rows = struct('Candidate', {}, 'Anchor', {}, 'Score', {}, 'Matches', {}, ...
    'Inliers', {}, 'InlierRatio', {}, 'Coverage', {}, 'Valid', {}, ...
    'Reason', {}, 'BBox', {});
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
                corners = [1,1; w,1; w,h; 1,h];
                projected = transformPointsForward(transform, corners);
                projected = (projected - 0.5) ./ cropRatio + 0.5 + boxes(c,1:2) - 1;
                [geometryOK, predictedBox] = validProjection(projected, frame, boxes(c,:));
                row.BBox = predictedBox;
                row.Valid = geometryOK && row.Inliers >= config.MinInliers && ...
                    row.InlierRatio >= config.MinInlierRatio && ...
                    row.Coverage >= config.MinAnchorCoverage;
                row.Reason = "geometric/support check failed";
                if row.Valid
                    row.Reason = "valid";
                    row.Score = row.Inliers * row.InlierRatio * sqrt(row.Coverage);
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

function [valid, box] = validProjection(polygon, image, proposal)
box = nan(1,4);
valid = false;
if any(~isfinite(polygon), 'all'), return; end
edges = polygon([2:4,1],:) - polygon;
next = edges([2:4,1],:);
cross = edges(:,1).*next(:,2) - edges(:,2).*next(:,1);
if ~(all(cross > 0) || all(cross < 0)), return; end
low = min(polygon,[],1);
high = max(polygon,[],1);
box = [low, high-low];
center = low + (high-low)/2;
frameBox = [1,1,size(image,2)-1,size(image,1)-1];
area = polyarea(polygon(:,1), polygon(:,2));
valid = all(box(3:4) > 4) && area > 25 && ...
    area / prod(box(3:4)) > 0.2 && ...
    area < 4*prod(proposal(3:4)) && ...
    centerInsideBBox(center, proposal) && centerInsideBBox(center, frameBox) && ...
    all(low >= 1 - 0.1*[size(image,2),size(image,1)]) && ...
    all(high <= 1.1*[size(image,2),size(image,1)]);
end
