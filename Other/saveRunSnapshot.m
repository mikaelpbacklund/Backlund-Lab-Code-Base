function savedPaths = saveRunSnapshot(ex,saveName,p,varargin)
% Saves a consistent run snapshot with derived analysis exports for manual,
% checkpoint, and final saves. -Div

if nargin < 2
   saveName = [];
end
if nargin < 3 || isempty(p)
   p = struct;
end

opts = struct(...
   'status','manual',...
   'checkpoint',false,...
   'saveDirectory',[],...
   'saveAverageContrastPNG',true,...
   'runStartTime',[],...
   'errorInfo',[],...
   'checkpointCount',0);
opts = parseSnapshotOptions(opts,varargin{:});

[matFilePath,baseFilePath] = resolveSnapshotPaths(saveName,opts.saveDirectory,ex,opts.checkpoint);

% Changed: snapshot files now keep the familiar raw variables while adding
% progress, metadata, and derived analysis in one shared format. -Div
Data = ex.data;
scanInfo = ex.scan;
params = p;
analysis = buildAnalysisExport(ex,p);
progress = buildProgressInfo(ex,p,opts);
metadata = buildMetadata(ex,opts,baseFilePath,progress);

% Changed: final and manual saves now emit an average-contrast PNG beside
% the MAT snapshot so later analysis has a quick visual reference. -Div
savedPaths = struct('matFile',matFilePath,'pngFile','');
if ~opts.checkpoint && opts.saveAverageContrastPNG
   [pngFilePath,pngError] = exportAverageContrastPNG(ex,analysis,baseFilePath);
   savedPaths.pngFile = pngFilePath;
   metadata.averageContrastPNG = pngFilePath;
   if ~isempty(pngError)
      metadata.averageContrastPNGError = pngError;
   end
end

saveSnapshotVariables(matFilePath,Data,scanInfo,params,progress,metadata,analysis);
savedPaths.matFile = matFilePath;
% Changed: a successful final save now removes the matching checkpoint file so
% completed runs do not leave stale recovery snapshots behind. -Div
if ~opts.checkpoint && strcmpi(opts.status,'completed')
   deleteCheckpointSnapshot(baseFilePath);
end

end

function opts = parseSnapshotOptions(opts,varargin)
if isempty(varargin)
   return
end

if rem(numel(varargin),2) ~= 0
   error('saveRunSnapshot options must be supplied as name/value pairs')
end

for ii = 1:2:numel(varargin)
   optionName = lower(string(varargin{ii}));
   optionValue = varargin{ii+1};

   switch optionName
      case "status"
         opts.status = char(string(optionValue));
      case "checkpoint"
         opts.checkpoint = logical(optionValue);
      case "savedirectory"
         opts.saveDirectory = optionValue;
      case "saveaveragecontrastpng"
         opts.saveAverageContrastPNG = logical(optionValue);
      case "runstarttime"
         opts.runStartTime = optionValue;
      case "errorinfo"
         opts.errorInfo = optionValue;
      case "checkpointcount"
         opts.checkpointCount = optionValue;
      otherwise
         error('Unknown saveRunSnapshot option "%s"',string(varargin{ii}))
   end
end
end

function [matFilePath,baseFilePath] = resolveSnapshotPaths(saveName,saveDirectory,ex,isCheckpoint)
defaultSaveDirectory = fullfile(fileparts(fileparts(mfilename('fullpath'))),'Saved Data');

if isempty(saveName)
   baseName = createDefaultSnapshotName(ex);
   fileDirectory = defaultSaveDirectory;
else
   [sentDirectory,baseName,~] = fileparts(char(saveName));
   if isempty(baseName)
      baseName = char(saveName);
   end

   if isempty(sentDirectory)
      if isempty(saveDirectory)
         fileDirectory = defaultSaveDirectory;
      else
         fileDirectory = char(saveDirectory);
      end
   else
      if isfolder(sentDirectory) || ~isempty(regexp(sentDirectory,'^[A-Za-z]:','once')) || startsWith(sentDirectory,filesep)
         fileDirectory = sentDirectory;
      else
         fileDirectory = fullfile(pwd,sentDirectory);
      end
   end
end

if isempty(baseName)
   baseName = createDefaultSnapshotName(ex);
end

if ~isfolder(fileDirectory)
   mkdir(fileDirectory)
end

baseFilePath = fullfile(fileDirectory,baseName);
if isCheckpoint
   matFilePath = strcat(baseFilePath,"__checkpoint.mat");
else
   matFilePath = strcat(baseFilePath,".mat");
end
matFilePath = char(matFilePath);
baseFilePath = char(baseFilePath);
end

function baseName = createDefaultSnapshotName(ex)
if ~isempty(ex.scan) && isfield(ex.scan(1),'notes') && ~isempty(ex.scan(1).notes)
   baseName = char(ex.scan(1).notes);
else
   baseName = 'ExperimentRun';
end

% Changed: auto-generated save names are sanitized and timestamped so
% unattended checkpoint/final files stay stable and copy-friendly. -Div
baseName = regexprep(baseName,'[^A-Za-z0-9_-]+','_');
baseName = regexprep(baseName,'_+','_');
baseName = regexprep(baseName,'^_|_$','');
if isempty(baseName)
   baseName = 'ExperimentRun';
end
baseName = sprintf('%s_%s',baseName,char(datetime('now','Format','yyyyMMdd_HHmmss')));
end

function progress = buildProgressInfo(ex,p,opts)
iterationMatrix = [];
if ~isempty(ex.data) && isstruct(ex.data) && isfield(ex.data,'iteration') && ~isempty(ex.data.iteration)
   iterationMatrix = ex.data.iteration;
end

if isempty(iterationMatrix)
   completedIterations = 0;
   currentIteration = 0;
   hasPartialIteration = false;
else
   completedIterations = min(iterationMatrix(:));
   currentIteration = max(iterationMatrix(:));
   hasPartialIteration = currentIteration > completedIterations;
end

progress = struct;
progress.status = opts.status;
progress.savedAt = datetime('now');
progress.completedIterations = completedIterations;
progress.currentIteration = currentIteration;
progress.hasPartialIteration = hasPartialIteration;
progress.iterationMatrix = iterationMatrix;
progress.odometer = ex.odometer;
progress.checkpointCount = opts.checkpointCount;
if isfield(p,'nIterations') && ~isempty(p.nIterations)
   progress.targetIterations = p.nIterations;
else
   progress.targetIterations = [];
end
end

function metadata = buildMetadata(ex,opts,baseFilePath,progress)
metadata = struct;
metadata.savedAt = progress.savedAt;
metadata.baseSavePath = baseFilePath;
metadata.saveType = ternaryValue(opts.checkpoint,'checkpoint','final');
metadata.runStatus = opts.status;
metadata.runStartTime = opts.runStartTime;
metadata.errorInfo = opts.errorInfo;
metadata.dataInfo = collectLegacyDataInfo(ex);

if ~isempty(ex.scan) && isfield(ex.scan(1),'notes')
   metadata.scanNotes = ex.scan(1).notes;
else
   metadata.scanNotes = '';
end

% Changed: structured save metadata now records the snapshot event directly
% in the MAT file instead of relying on a separate diary/log file. -Div
metadata.log.events = {struct(...
   'time',progress.savedAt,...
   'status',opts.status,...
   'checkpoint',logical(opts.checkpoint),...
   'completedIterations',progress.completedIterations,...
   'currentIteration',progress.currentIteration)};
end

function dataInfo = collectLegacyDataInfo(ex)
dataInfo = {};
n = 0;

% Changed: the older saveData instrument summary is preserved inside
% metadata.dataInfo so existing analysis habits still have the same context. -Div
if ~isempty(ex.SRS_RF)
   n = n+1;
   dataInfo{n,1} = 'RF frequency';
   dataInfo{n,2} = ex.SRS_RF.frequency;
   n = n+1;
   dataInfo{n,1} = 'RF amplitude';
   dataInfo{n,2} = ex.SRS_RF.amplitude;
end

if ~isempty(ex.pulseBlaster)
   n = n+1;
   dataInfo{n,1} = 'Pulse sequence';
   dataInfo{n,2} = ex.pulseBlaster.sequenceSentToPulseBlaster;
   n = n+1;
   dataInfo{n,1} = 'Number of loops for pulse sequence';
   dataInfo{n,2} = ex.pulseBlaster.nTotalLoops;
end

if ~isempty(ex.hamm)
   n = n+1;
   dataInfo{n,1} = 'Frames per trigger';
   dataInfo{n,2} = ex.hamm.framesPerTrigger;
   n = n+1;
   dataInfo{n,1} = 'Exposure time';
   dataInfo{n,2} = ex.hamm.exposureTime;
end

if ~isempty(ex.scan)
   n = n+1;
   dataInfo{n,1} = 'Scan info';
   dataInfo{n,2} = ex.scan;
end
end

function analysis = buildAnalysisExport(ex,p)
analysis = struct;

if isempty(ex.scan) || isempty(ex.data) || ~isfield(ex.data,'iteration') || isempty(ex.data.iteration)
   return
end

scanDimension = numel(ex.scan);
analysis.dimension = scanDimension;

[averageContrast,averageReference,averageSignal,averageSNR] = computeAverageMetricArrays(ex,p);

% Changed: saved analysis exports are computed from raw stored data with
% NaNs for incomplete points instead of reusing display-only plot buffers. -Div
if scanDimension == 1
   [xAxis,xLabel] = buildAxisData(ex.scan(1),p,true);
   analysis.averageContrast = struct('x',xAxis,'y',averageContrast,'xLabel',xLabel,'yLabel','Contrast');
   analysis.averageReference = struct('x',xAxis,'y',averageReference,'xLabel',xLabel,'yLabel','Reference');
   analysis.averageSignal = struct('x',xAxis,'y',averageSignal,'xLabel',xLabel,'yLabel','Signal');
   analysis.averageSNR = struct('x',xAxis,'y',averageSNR,'xLabel',xLabel,'yLabel','SNR (arbitrary units)');
elseif scanDimension == 2
   [yAxis,yLabel] = buildAxisData(ex.scan(1),p,false);
   [xAxis,xLabel] = buildAxisData(ex.scan(2),p,false);
   analysis.averageContrast = struct('x',xAxis,'y',yAxis,'z',averageContrast,'xLabel',xLabel,'yLabel',yLabel,'zLabel','Contrast');
   analysis.averageReference = struct('x',xAxis,'y',yAxis,'z',averageReference,'xLabel',xLabel,'yLabel',yLabel,'zLabel','Reference');
   analysis.averageSignal = struct('x',xAxis,'y',yAxis,'z',averageSignal,'xLabel',xLabel,'yLabel',yLabel,'zLabel','Signal');
   analysis.averageSNR = struct('x',xAxis,'y',yAxis,'z',averageSNR,'xLabel',xLabel,'yLabel',yLabel,'zLabel','SNR (arbitrary units)');
else
   analysis.averageContrast = struct('values',averageContrast);
   analysis.averageReference = struct('values',averageReference);
   analysis.averageSignal = struct('values',averageSignal);
   analysis.averageSNR = struct('values',averageSNR);
end
end

function [averageContrast,averageReference,averageSignal,averageSNR] = computeAverageMetricArrays(ex,p)
invertSignalForSNR = isfield(p,'invertSignalForSNR') && logical(p.invertSignalForSNR);

if isscalar(ex.scan)
   averageContrast = nan(1,ex.scan.nSteps);
   averageReference = nan(1,ex.scan.nSteps);
   averageSignal = nan(1,ex.scan.nSteps);
   averageSNR = nan(1,ex.scan.nSteps);

   for ii = 1:ex.scan.nSteps
      currentIteration = ex.data.iteration(ii);
      if currentIteration <= 0
         continue
      end

      currentData = createDataMatrixWithIterations(ex,ii);
      if any(isnan(currentData),"all")
         continue
      end

      averageData = mean(currentData,2);
      if isscalar(averageData)
         averageData(2) = 0;
      end

      referenceValue = averageData(1);
      signalValue = averageData(2);
      contrastValue = computeContrastValue(referenceValue,signalValue);
      currentNPoints = ex.data.nPoints(ii,1:currentIteration);
      currentNPoints = currentNPoints(currentNPoints > 0);

      averageContrast(ii) = contrastValue;
      averageReference(ii) = referenceValue;
      averageSignal(ii) = signalValue;
      averageSNR(ii) = computeSNRValue(referenceValue,contrastValue,currentNPoints,invertSignalForSNR);
   end
   return
end

iterationMatrix = ex.data.iteration;
arraySize = size(iterationMatrix);

averageContrast = nan(arraySize);
averageReference = nan(arraySize);
averageSignal = nan(arraySize);
averageSNR = nan(arraySize);

indexCells = cell(1,ndims(iterationMatrix));
for ii = 1:numel(iterationMatrix)
   [indexCells{:}] = ind2sub(arraySize,ii);
   currentIteration = iterationMatrix(indexCells{:});
   if currentIteration <= 0
      continue
   end

   currentData = createDataMatrixWithIterations(ex,cell2mat(indexCells));
   if any(isnan(currentData),"all")
      continue
   end

   averageData = mean(currentData,2);
   if isscalar(averageData)
      averageData(2) = 0;
   end

   referenceValue = averageData(1);
   signalValue = averageData(2);
   contrastValue = computeContrastValue(referenceValue,signalValue);
   currentNPoints = ex.data.nPoints(indexCells{:},1:currentIteration);
   currentNPoints = currentNPoints(currentNPoints > 0);

   averageContrast(ii) = contrastValue;
   averageReference(ii) = referenceValue;
   averageSignal(ii) = signalValue;
   averageSNR(ii) = computeSNRValue(referenceValue,contrastValue,currentNPoints,invertSignalForSNR);
end
end

function contrastValue = computeContrastValue(referenceValue,signalValue)
if isempty(referenceValue) || referenceValue == 0 || isnan(referenceValue)
   contrastValue = nan;
   return
end
contrastValue = (referenceValue - signalValue) / referenceValue;
end

function snrValue = computeSNRValue(referenceValue,contrastValue,nPoints,invertSignalForSNR)
if isempty(referenceValue) || isnan(referenceValue) || referenceValue <= 0 || isempty(contrastValue) || isnan(contrastValue)
   snrValue = nan;
   return
end

if invertSignalForSNR
   if contrastValue == 0
      snrValue = nan;
      return
   end
   snrValue = sqrt(referenceValue) * contrastValue^(-1);
else
   snrValue = sqrt(referenceValue) * contrastValue;
end

if isempty(nPoints)
   snrValue = nan;
   return
end
snrValue = snrValue * sqrt(mean(nPoints,"all"));
end

function [axisData,axisLabel] = buildAxisData(scanInfo,p,applyOffset)
axisIndex = 1;
if isfield(p,'boundsToUse') && ~isempty(p.boundsToUse) && isscalar(p.boundsToUse)
   axisIndex = p.boundsToUse;
end

if isa(scanInfo.bounds,'cell')
   bounds = scanInfo.bounds{min(axisIndex,numel(scanInfo.bounds))};
else
   bounds = scanInfo.bounds;
end

nSteps = scanInfo.nSteps;
if isa(nSteps,'cell')
   nSteps = nSteps{min(axisIndex,numel(nSteps))};
end

axisData = linspace(bounds(1),bounds(2),nSteps);
if applyOffset && isfield(p,'xOffset') && ~isempty(p.xOffset)
   axisData = axisData + p.xOffset;
end
axisLabel = scanInfo.parameter;
end

function [pngFilePath,pngError] = exportAverageContrastPNG(ex,analysis,baseFilePath)
pngFilePath = strcat(baseFilePath,"_AverageContrast.png");
pngFilePath = char(pngFilePath);
pngError = '';

try
   averageContrastFigure = [];
   if isstruct(ex.plots) && isfield(ex.plots,'Average_Contrast') && isfield(ex.plots.Average_Contrast,'figure') && ishandle(ex.plots.Average_Contrast.figure)
      averageContrastFigure = ex.plots.Average_Contrast.figure;
   end

   if isempty(averageContrastFigure)
      averageContrastFigure = figure('Visible','off','Name','Average Contrast','NumberTitle','off');
      cleanupFigure = onCleanup(@()close(averageContrastFigure));

      if isfield(analysis,'dimension') && analysis.dimension == 1 && isfield(analysis,'averageContrast')
         plot(analysis.averageContrast.x,analysis.averageContrast.y)
         xlabel(analysis.averageContrast.xLabel)
         ylabel(analysis.averageContrast.yLabel)
         title('Average Contrast')
      elseif isfield(analysis,'dimension') && analysis.dimension == 2 && isfield(analysis,'averageContrast')
         imagesc(analysis.averageContrast.x,analysis.averageContrast.y,analysis.averageContrast.z)
         xlabel(analysis.averageContrast.xLabel)
         ylabel(analysis.averageContrast.yLabel)
         title('Average Contrast')
         colorbar
         set(gca,'YDir','normal')
      else
         pngError = 'Average contrast PNG export skipped because no 1D or 2D analysis export was available.';
         return
      end

      exportgraphics(averageContrastFigure,pngFilePath)
      clear cleanupFigure
      return
   end

   exportgraphics(averageContrastFigure,pngFilePath)
catch ME
   pngFilePath = '';
   pngError = ME.message;
end
end

function saveSnapshotVariables(savePath,Data,scanInfo,params,progress,metadata,analysis)
try
   save(savePath,"Data","scanInfo","params","progress","metadata","analysis")
catch ME
   if contains(ME.message,'2GB') || contains(lower(ME.message),'7.3')
      % Changed: snapshots fall back to MAT v7.3 only when needed so normal
      % checkpoint saves stay lightweight while large runs still serialize. -Div
      save(savePath,"Data","scanInfo","params","progress","metadata","analysis","-v7.3")
   else
      rethrow(ME)
   end
end
end

function deleteCheckpointSnapshot(baseFilePath)
checkpointPath = strcat(baseFilePath,"__checkpoint.mat");
checkpointPath = char(checkpointPath);

if ~isfile(checkpointPath)
   return
end

try
   delete(checkpointPath)
catch
end
end

function out = ternaryValue(condition,trueValue,falseValue)
if condition
   out = trueValue;
else
   out = falseValue;
end
end