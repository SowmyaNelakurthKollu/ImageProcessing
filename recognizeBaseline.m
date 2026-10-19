function result = recognizeBaseline(frame, anchorImages, threshold, config, boxes)
if nargin < 4, config = projectConfig(); end
if nargin < 5, boxes = generateCandidates(frame, config); end
n = size(boxes,1);
scores = zeros(n,1);
anchors = zeros(n,1);
anchorDescriptors = cellfun(@colorDescriptor, anchorImages, 'UniformOutput', false);
for k = 1:n
    descriptor = colorDescriptor(imcrop(frame, boxes(k,:)));
    similarities = cellfun(@(a) sum(sqrt(a .* descriptor)), anchorDescriptors);
    [scores(k), anchors(k)] = max(similarities);
end
[scores, order] = sort(scores, 'descend');
result.candidates = table(order, anchors(order), scores, boxes(order,:), ...
    'VariableNames', {'Candidate','Anchor','Score','BBox'});
result.score = 0;
result.bestAnchor = 0;
result.bbox = [];
result.center = [];
result.valid = n > 0;
if result.valid
    result.score = scores(1);
    result.bestAnchor = anchors(order(1));
    result.bbox = boxes(order(1),:);
    result.center = result.bbox(1:2) + result.bbox(3:4)/2;
end
result.targetPresent = result.valid && result.score >= threshold;
end
