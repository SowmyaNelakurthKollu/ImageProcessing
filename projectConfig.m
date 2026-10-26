function config = projectConfig()
root = fileparts(mfilename('fullpath'));
config.Root = root;
config.LocalDataSave = 'C:\Users\sowmy\OneDrive - Luleå University of Technology\Project_3';
config.RawFolder = 'C:\Users\sowmy\OneDrive - Luleå University of Technology\Project_3\raw';
config.EvalFolder = fullfile(config.RawFolder, 'eval');
config.CameraColorImageRawFolder = fullfile(config.EvalFolder, 'camera_color_image_raw');
config.AnchorFolder = fullfile(root, 'Anchor_Images');
config.AnchorBoxes = fullfile(root, 'annotations', 'anchor_boxes.csv');
config.LabelFile = fullfile(root, 'annotations', 'frames.csv');
config.ResultsFolder = fullfile(root, 'results');
config.Seed = 2026;
config.MaxFramesPerSequence = 40;
config.SplitBlockLength = 20;
config.SplitGuardFrames = 2;
config.MaxImageSide = 1280;
config.CandidateSide = 640;
config.MaxCandidates = 20;
config.MinimumRedPixels = 20;
config.AnchorSide = 330;

% Matching gates. Starting values from the slide-style discussion; tune on validation only.
config.MatchRatio = 0.75;          % was 0.75
config.MinInliers = 5;             % was 4
config.MinInlierRatio = 0.3;        % was 0.35, then 0.15
config.MinAnchorCoverage = 0.02;
config.MaxReprojectionError = 4;

% Replica rejection. A real-anchor candidate is dropped if a replica anchor
% scores at least ReplicaMargin times the real score. Tune on validation only.
config.ReplicaMargin = 0.8;

config.PrecisionTarget = 0.55;
config.RecallTarget = 0.50;
config.MinBoxFraction = 0.1;

% Geometry sanity checks for the SIFT transform (rejects sliver/collapsed boxes).
config.TransformType = 'similarity';
config.MaxAnisotropy = 1.6;
config.MaxShear = 0.3;
config.MaxRotationDeg = 30;
config.MaxSizeRatio = 2.5;

% Localization: SIFT verifies, red-cylinder box localizes.
config.UseColorBox = true;
config.ColorBoxHeadroom = 0.35;

% Evaluation: a detection must also overlap the reference box.
config.MinIoU = 0.3;
end

%[appendix]{"version":"1.0"}
%---
