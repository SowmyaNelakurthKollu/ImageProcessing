%% =========================================================
% CREATE GROUND TRUTH
% Manually label the target object in color frames
% ==========================================================

clear;
close all;
clc;

%% =========================================================
% 1. DATASET PATH
% ==========================================================

datasetFolder = ...
    'C:\Users\sowmy\OneDrive - Luleå University of Technology\Project_3\raw\eval\camera_color_image_raw';

%% =========================================================
% 2. FIND COLOR IMAGES
% ==========================================================

files = dir(fullfile(datasetFolder,'camera_color_image_*'));

if isempty(files)
    error('No color images found. Check datasetFolder.');
end

fprintf('Number of color frames found: %d\n',length(files));

%% =========================================================
% 3. HOW MANY FRAMES TO LABEL
% ==========================================================

% Start with 50 frames.
% You can increase this later.

numFramesToLabel = min(50,length(files));

fprintf('Frames to label: %d\n',numFramesToLabel);

%% =========================================================
% 4. CREATE GROUND TRUTH TABLE
% ==========================================================

Frame = strings(numFramesToLabel,1);

TargetPresent = false(numFramesToLabel,1);

X = nan(numFramesToLabel,1);
Y = nan(numFramesToLabel,1);
Width = nan(numFramesToLabel,1);
Height = nan(numFramesToLabel,1);

%% =========================================================
% 5. LABEL EACH IMAGE
% ==========================================================

for k = 1:numFramesToLabel

    fprintf('\n========================================\n');
    fprintf('Frame %d / %d\n',k,numFramesToLabel);
    fprintf('========================================\n');

    %% Load image

    framePath = fullfile( ...
        files(k).folder, ...
        files(k).name);

    img = imread(framePath);

    %% Display image

    figure(1);
    imshow(img);
    title(sprintf( ...
        'Frame %d/%d - Is the target present?', ...
        k,numFramesToLabel));

    %% Save frame name

    Frame(k) = string(files(k).name);

    %% Ask whether target exists

    answer = input( ...
        'Is the target object present? (y/n): ', ...
        's');

    answer = lower(strtrim(answer));

    %% Target present

    if strcmp(answer,'y')

        fprintf('\nDraw a rectangle around the TARGET OBJECT.\n');
        fprintf('Click and drag around the entire object.\n');

        title('Draw rectangle around TARGET, then double-click inside');

        %% Draw bounding box

        rectangleHandle = drawrectangle;

        %% Wait until user finishes drawing

        wait(rectangleHandle);

        %% Get rectangle position

        position = rectangleHandle.Position;

        % position =
        % [x y width height]

        X(k) = position(1);
        Y(k) = position(2);
        Width(k) = position(3);
        Height(k) = position(4);

        TargetPresent(k) = true;

        fprintf('\nBounding box recorded:\n');
        fprintf('X      = %.2f\n',X(k));
        fprintf('Y      = %.2f\n',Y(k));
        fprintf('Width  = %.2f\n',Width(k));
        fprintf('Height = %.2f\n',Height(k));

    %% Target absent

    elseif strcmp(answer,'n')

        TargetPresent(k) = false;

        fprintf('Target marked as ABSENT.\n');

    else

        fprintf('Invalid answer. Please enter y or n.\n');

        k = k - 1;
        continue;

    end

    %% Close image

    close(1);

end

%% =========================================================
% 6. CREATE TABLE
% ==========================================================

groundTruth = table( ...
    Frame, ...
    TargetPresent, ...
    X, ...
    Y, ...
    Width, ...
    Height);

%% =========================================================
% 7. SAVE CSV
% ==========================================================

outputFile = 'ground_truth.csv';

writetable(groundTruth,outputFile);

fprintf('\n========================================\n');
fprintf('GROUND TRUTH CREATED\n');
fprintf('========================================\n');

fprintf('File: %s\n',fullfile(pwd,outputFile));

fprintf('Number of frames labeled: %d\n',height(groundTruth));

disp(groundTruth);