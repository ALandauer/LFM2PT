%main run script to run LFM2PT: coolect data, configure and run reconstruction, run Trial-MPT, and save output.


% This project is based on two underlaying packages: oLaF for
% reconstruction and Trial-MPT for particle tracking.
%
% See:  A Stefanoiu, J Page, P Symvoulidis, GG Westmeyer, and T Lasser,
%       "Artifact-free deconvolution in light field microscopy,"
%       Opt. Express 27, 31644-31666 (2019)
%
%       and
%
%       [Jin's Trial-MPT paper]
%

%% Add dependecy dirs to path
import2ws();


%% Specify data to import
data_folder = ['.',filesep,'data'];
dataset = 'dx_exp';

%% Set up run parameters

% ----------------------- oLaF parameters -----------------------

%reconstruction depth range (im um)
depthRange = [-10, 1500];
% axial slice step (in um)
depthStep = 5;

% choose lenslet spacing (in  pixels) to downsample the number of pixels between mlens for speed up
newSpacingPx = 15; % 'default' means no up/down-sampling (newSpacingPx = lensPitch/pixelPitch)
% choose super-resolution factor as a multiple of lenslet resolution (= 1 voxel/lenslet)
superResFactor = 'default'; % default means sensor resolution

[LensletImageSeq, imageNames, WhiteImage, configFile] = LFM_selectImages(dataset);

figure; imagesc(LensletImageSeq{1}); colormap inferno; title ('LF image #1'); drawnow

%% Specific LFM configuration and camera parameters (um units)
Camera = LFM_setCameraParams(configFile, newSpacingPx);

%% Compute LFPSF Patterns and other prerequisites: lenslets centers, resolution related
[LensletCenters, Resolution, LensletGridModel, NewLensletGridModel] = ...
    LFM_computeGeometryParameters(Camera, WhiteImage, depthRange, depthStep, superResFactor, 1);

[H, Ht] = LFM_computeLFMatrixOperators(Camera, Resolution, LensletCenters);

%% Correct the input image
% obtain the transformation between grid models
FixAll = LFM_retrieveTransformation(LensletGridModel, NewLensletGridModel);

% apply the transformation to the lenslet and white images
for ii = 1:length(LensletImageSeq)
    [correctedLensletImageSeq{ii}, correctedWhiteImage] = LFM_applyTransformation(LensletImageSeq{ii}, WhiteImage, FixAll, LensletCenters, 1);
    correctedLensletImageSeq{ii}(correctedLensletImageSeq{ii} < mean(correctedLensletImageSeq{ii}(:))) = mean(correctedLensletImageSeq{ii}(:));
    correctedLensletImageSeq{ii} = mat2gray(single(correctedLensletImageSeq{ii}));
end
%% Reconstruct

for ii = 1:length(LensletImageSeq)
% precompute image/volume sizes
imgSize = size(correctedLensletImageSeq{ii});
imgSize = imgSize + (1-mod(imgSize,2)); % ensure odd size

texSize = ceil(imgSize.*Resolution.texScaleFactor);
texSize = texSize + (1-mod(texSize,2)); % ensure odd size

% Setup function pointers
if (strcmp(Camera.focus, 'single'))
    backwardFUN = @(projection) LFM_backwardProject(Ht, projection, LensletCenters, Resolution, texSize, Camera.range);
    forwardFUN = @(object) LFM_forwardProject(H, object, LensletCenters, Resolution, imgSize, Camera.range);
elseif (strcmp(Camera.focus, 'multi'))
    backwardFUN = @(projection) LFM_backwardProjectMultiFocus(Ht, projection, LensletCenters, Resolution, texSize, Camera.range);
    forwardFUN = @(object) LFM_forwardProjectMultiFocus(H, object, LensletCenters, Resolution, imgSize, Camera.range);
else
    error('Invalid micro-lens type.')
end

% build anti-aliasing filter kernels
lanczosWindowSize = 2;
widths = LFM_computeDepthAdaptiveWidth(Camera, Resolution);
lanczos2FFT = LFM_buildAntiAliasingFilter([texSize, length(Resolution.depths)], widths, lanczosWindowSize);

% Apply EMS deconvolution
it = 3;

% initialization
initVolume = ones([texSize, length(Resolution.depths)]);
LFimage = correctedLensletImageSeq{ii};

% background correction
onesvol = ones(size(initVolume));
onesForward = forwardFUN(onesvol);
onesBack = backwardFUN(onesForward);

reconVolume = deconvEMS(forwardFUN, backwardFUN, LFimage, it, initVolume, 1, lanczos2FFT, onesForward, onesBack);

% Display the first reconstruction
if ii == 1
figure;
if(size(reconVolume, 3) > 1)
    imshow3D(reconVolume, [], 'inferno');
else
    imagesc(reconVolume); colormap inferno
end


%verify with user if it is okay
prompt = 'Continue deconvolving the remainder of the sequence? Y/N [Y]: ';
yn = input(prompt,'s');
if isempty(yn)
    yn = 'Y';
end
if yn == 'y' || yn == 'Y'
    disp('Onward!')
else
    error('Deconv not accepted...')
end
end

%save out the recon'd image
save([imageNames{ii}(1:end-4),'.mat'],'reconVolume','LensletImage')

end


