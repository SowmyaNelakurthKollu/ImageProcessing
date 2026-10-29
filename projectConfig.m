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
% Label only these raw sequences. The eval sequence has no target-absent
% frames, so makeEvalNegatives adds crops of each frame that exclude the target.
config.LabelSequences = "eval";
config.NegativeFolder = fullfile('derived', 'eval_negatives');   % under LocalDataSave
config.NegativeMargin = 0.25;    % gap beside the target box, as a fraction of its width
config.NegativeMinWidth = 64;    % pixels
config.AllowPresentOnlySplits = true;
config.MaxImageSide = 1280;
config.CandidateSide = 640;
config.MaxCandidates = 20;
config.MinimumRedPixels = 20;
config.AnchorSide = 330;

% Matching gates. Starting values from the slide-style discussion; tune on validation only.
config.MatchRatio = 0.75;          % was 0.75
config.MinInliers = 3;             % similarity needs 2 points, so 3 is still a real check
config.MinInlierRatio = 0.1;       % true support is only ~3-5 of ~20 matches at 640x400
config.MinAnchorCoverage = 0.02;
config.MaxReprojectionError = 4;   % in frame pixels (scaled by the crop upsampling)

% Replica rejection. A real-anchor candidate is dropped if a replica anchor
% scores at least ReplicaMargin times the real score. Tune on validation only.
config.ReplicaMargin = 0.8;

config.PrecisionTarget = 0.75;   % assignment target
config.RecallTarget = 0.60;      % assignment target
config.MinBoxFraction = 0.1;

% Geometry sanity checks for the SIFT transform (rejects sliver/collapsed boxes).
config.TransformType = 'similarity';
config.MaxAnisotropy = 1.6;
config.MaxShear = 0.3;
config.MaxRotationDeg = 30;
config.MaxSizeRatio = 2.5;

% Verification: 'matches' scores each red proposal by its number of SIFT
% matches to the anchors; 'geometry' also requires a RANSAC similarity fit.
config.Verification = 'matches';
config.MinMatches = 2;

% Localization box: 'proposal' (red cylinder + hose, same as the colour
% baseline), 'red' (cylinder + ColorBoxHeadroom) or 'sift' (projected anchor).
config.LocalizationBox = 'proposal';
config.ColorBoxHeadroom = 0.35;

% Evaluation. Set MinIoU > 0 to additionally require box overlap (stricter than the brief).
config.MinIoU = 0;   % assignment rule: predicted center inside reference box; IoU is still reported as MeanIoU
end

%[appendix]{"version":"1.0"}
%---
