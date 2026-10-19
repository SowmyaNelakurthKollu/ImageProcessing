# Anchor-Based Object Recognition and Localization

MATLAB code for recognizing the **same physical fire extinguisher** shown in
three provided anchor images. Printed pictures of the target are negatives.
This branch contains the implementation, annotation workflow and tests, not
submission-generation tooling or presentation deliverables.

## Requirements

- MATLAB R2024b or later.
- Computer Vision Toolbox and Image Processing Toolbox.
- No GPU or Python required.
- Supplied anchors and RGB dataset, stored locally:

```text
ImageProcessing\
  Anchor_Images\Anchor1.png
  Anchor_Images\Anchor2.png
  Anchor_Images\Anchor3.png
  raw\eval\camera_color_image_raw\*.png
  raw\test\camera_color_image_raw\*.png
```

The supplied data has 126 RGB frames in `eval` and 93 in `test`. Data and
generated outputs are excluded from Git. Obtain the data from the course
resources; the implementation does not upload it or download models.

## Testing and running

### 1. Run regression tests in MATLAB

```matlab
cd('C:\gtt\CV\ImageProcessing')
ver
testResults = runtests('tests');
assertSuccess(testResults)
```

Tests cover TP/FP/FN counting, frame-ID alignment, invalid/unreviewed labels,
undefined denominators, localization-aware threshold selection, proposal
generation, zero-threshold rejection and synthetic SIFT localization.
These tests do not require the supplied dataset or manual labels.

**Validation status:** MATLAB's command-line launcher failed with MathWorks
services error 5201 in the development environment. MATLAB tests and real-data
accuracy have not been verified. If interactive MATLAB works, run these
commands there and retain the output; do not infer that tests passed.

### 2. Create reference annotations

```matlab
config = projectConfig();
labelAnchors(config)
prepareAnnotations(config)
labelProject(config)
```

Draw three tight whole-object anchor boxes, including the hose but excluding
as much room background as practical. Double-click each rectangle to confirm.

For each frame, select Present, Absent or Stop. Printed replicas alone are
**Absent**. When the real target is present, draw its whole-object box,
including the hose. Also select the visible distractor type.

Frame annotations are saved after each completed frame. Stop/cancel leaves
the current frame unreviewed. Resume with `labelProject(config)`.
`TargetPresent=NaN` means unknown, never absent. Evaluation requires all
frames to be reviewed.

Annotation tools refuse to overwrite existing manifests or anchor boxes.
To revise a frame, set its `Reviewed` field to `0` in
`annotations\frames.csv`, then resume. Move
`annotations\anchor_boxes.csv` aside before relabeling anchors.

### 3. Evaluate both methods

```matlab
summary = runProject(config)
exportDemo(config)
```

Alternatively, run `Project` for the complete workflow: resumable annotation,
tests, experiment and annotated visualization export.
Use `Project.m`, **not** the legacy `Project.mlx`, which has old paths and
incompatible prototype evaluation logic.

The default manifest selects 40 frames per sequence, for 80 reviewed frames.
It alternates 20-frame validation/evaluation blocks, excludes two frames on
each side of a block boundary, then samples retained frames evenly.
The source folders `eval` and `test` are **not** the split names.
This within-sequence split gives both subsets access to the printed-replica
portion, but does not provide independent-scene evaluation.

Both subsets must contain positives and negatives. Freeze the manifest before
looking at predictions. For more frames, increase
`config.MaxFramesPerSequence` before preparing a new manifest. Do not remove
hard frames or tune parameters using held-out outcomes.

## Methods

Both systems share red-region proposals. Resize frames to at most 960 px on
the longest side. Threshold HSV red (`H<0.065 or H>0.94`, `S>0.45`, `V>0.12`),
close with a radius-2 disk and retain components of at least 20 pixels.
Keep regions at least 8 px tall, with height/width in [1.2,15], then expand
upward and sideways to include the hose. Retain up to 20 proposals by red area.
These are initial design choices, not empirically validated optimal settings.

**Baseline:** normalized 16 hue x 4 saturation histograms; compare each
proposal to all anchors using `sum(sqrt(anchor .* candidate))`. Rank by
maximum similarity and output the best proposal box above threshold.

**Final:** object-cropped anchor SIFT features; proposals resized to a
480 px longest side; unique descriptor matching with ratio 0.75. Projective
RANSAC uses 2,000 trials, 99% confidence and a 4 px residual limit in resized
proposal coordinates. Require at least 6 inliers, inlier ratio 0.35 and anchor
bounding-span coverage 0.02. Reject nonfinite, nonconvex or implausibly
placed/sized projections.

Rank valid region-anchor hypotheses by
`inliers * inlierRatio * sqrt(coverage)`. Project the cropped anchor corners
and output their enclosing axis-aligned box in original frame coordinates.
No valid hypothesis means absent, even at threshold zero. Log rejected
hypotheses and their reasons instead of hiding RANSAC failures.

**Calibration:** separate thresholds for baseline and final method. Test
unique validation scores, 0 and reject-all (`Inf`). Choose best F1 among
thresholds meeting precision >=0.75 and recall >=0.60. If none qualify,
warn and choose best F1 without claiming success. Ties prefer precision,
then a higher threshold. Freeze thresholds before held-out evaluation.
The random seed is fixed at 2026.

## Evaluation rules

- Align predictions and references by exact, unique frame IDs.
- Correct localization: predicted box center inside the reference box,
  inclusive edges, as required by the assignment (not IoU).
- TP: real target, accepted and correctly localized.
- FP: any acceptance that is not TP.
- FN: real target without a correctly localized acceptance.
- A mislocalized acceptance in a positive frame counts as **both FP and FN**.
- Precision = TP / all acceptances; recall = TP / real-target frames.
- Localization success = correct localizations / all acceptances, with count
  and percentage; this equals precision for one acceptance per frame.
- Zero denominators return 0 plus explicit `*Defined=false` flags.

Candidate-center recall is a separate proposal diagnostic, not detector recall.
Anchor-win counts show usage, not causal contribution. Timings include matching
and shared proposal generation, excluding image I/O and one-time anchor setup.

## Outputs

`results` contains:

- `summary.json`: measured metrics, counts, thresholds, target flags,
  configuration, MATLAB version and toolboxes. Infinite thresholds become
  JSON `null`; the MAT file retains the original value.
- `{baseline,final}_predictions.csv`: scores, validity, acceptance, winning
  anchor, original-coordinate boxes/centers and processing time.
- `{baseline,final}_candidates.csv`: ranked hypotheses and matching evidence.
- `{baseline,final}_thresholds.csv`: validation-only threshold sweeps.
- `{baseline,final}_outcomes.csv`: held-out TP/FP/FN/TN/localization flags.
- `labels_snapshot.csv` and `anchor_boxes_snapshot.csv`: reviewed references.
- `experiment.mat`: hypotheses, polygons, inlier correspondences and thresholds.
- `visualizations\frame_*.jpg` and `demonstration.mp4`: held-out overlays,
  cyan reference, yellow baseline and green final.

Playback at 3 fps is for inspection, not a processing-speed claim.
Runs overwrite generated outputs and invalidate previous success artifacts.
Copy a completed results folder elsewhere before another run to retain it.

## Limitations

Red proposals can miss occluded, small or poorly illuminated targets.
Loose anchor crops can match the room instead of the object.
A homography approximates a nonplanar extinguisher and may fail with viewpoint
changes. Printed replicas can preserve excellent SIFT correspondences and
valid geometry: **RGB matching does not establish physical authenticity**.
Depth/infrared data are not used, and synchronized depth or temporal parallax
would require separate implementation and evaluation.

No measured accuracy claim is made until reviewed annotations, passing MATLAB
tests and a completed held-out experiment are available.
