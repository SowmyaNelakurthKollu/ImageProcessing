function [anchorImages, anchorFeatures, anchorValidPoints] = setupAnchors(anchorFolder)

%% =========================================================
% SETUP ANCHORS
% Load the 3 anchor images and extract SIFT features
% ==========================================================

anchorFiles = {
    fullfile(anchorFolder, 'Anchor1.png')
    fullfile(anchorFolder, 'Anchor2.png')
    fullfile(anchorFolder, 'Anchor3.png')
    };

numAnchors = length(anchorFiles);

anchorImages = cell(1,numAnchors);
anchorFeatures = cell(1,numAnchors);
anchorValidPoints = cell(1,numAnchors);

for i = 1:numAnchors

    %% Check file

    if ~isfile(anchorFiles{i})
        error('Anchor file not found: %s', anchorFiles{i});
    end

    %% Read image

    anchorImages{i} = imread(anchorFiles{i});

    %% Convert to grayscale

    if size(anchorImages{i},3) == 3
        grayImage = rgb2gray(anchorImages{i});
    else
        grayImage = anchorImages{i};
    end

    %% Detect SIFT

    points = detectSIFTFeatures(grayImage);

    %% Extract descriptors

    [features, validPoints] = ...
        extractFeatures(grayImage, points);

    anchorFeatures{i} = features;
    anchorValidPoints{i} = validPoints;

    fprintf('Anchor %d: %d SIFT features\n', ...
        i, validPoints.Count);

end

end