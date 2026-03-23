function ex = runScan(ex,p)
%Runs scan using experiment object
%p is parameter object

mustContainField(p,'collectionType')

paramsWithDefaults = {'plotAverageContrast',true;...
   'plotAverageReference',true;...
   'plotCurrentContrast',true;...
   'plotCurrentReference',true;...
   'plotAverageSNR',false;...
   'plotCurrentSNR',false;...
   'plotCurrentDataPoints',false;...
   'plotAverageDataPoints',false;...
   'plotCurrentSignal',false;...%not given as parameter elsewhere
   'plotAverageSignal',false;...%not given as parameter elsewhere
   'plotCurrentContrastFFT',false;...
   'plotAverageContrastFFT',false;...
   'verticalLineInfo',[];...
   'normalizeFFTByMagnet',false;...
   'plotPulseSequence',false;...
   'invertSignalForSNR',false;...
   'baselineSubtraction',0;...
   'boundsToUse',1;...
   'perSecond',true;...
   'nIterations',1;...
   'xOffset',0;...
   'resetData',true;...
   'nonInteractive',false;...
   'autoContinueOnTimeout',true;...
   'saveName',[];...
   'saveDirectory',[];...
   'autoSaveEveryIteration',true;...
   'saveAverageContrastPNG',true};

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

% Changed: save defaults are resolved once up front so checkpoints and the
% final save all write to the same stable base path. -Div
saveSettings = resolveRunSaveSettings(ex,p);
[startIteration,hasPartialIteration,resumePreviousPoint,completedIterations] = determineResumeState(ex,p);
%Sends information to the command window
if p.resetData
   iterationsForInfo = p.nIterations;
else
   iterationsForInfo = max(p.nIterations - completedIterations,0);
end
scanStartInfo(prod([ex.scan.nSteps]),ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,iterationsForInfo,.28)

% Changed: added shared prompt options and a pre-prompt DAQ stop/flush so the
% continuous NI task cannot keep filling its hardware/software buffers while the
% scan is idle at a prompt. -Div
promptOptions = struct('nonInteractive',p.nonInteractive,'autoContinueOnTimeout',p.autoContinueOnTimeout);
ex.DAQ = stopCollection(ex.DAQ,true);

runStartTime = datetime('now');
checkpointCount = 0;
runStatus = 'stopped';
runHasSavableState = ~p.resetData && ~isempty(ex.data) && isstruct(ex.data) && isfield(ex.data,'iteration') && ~isempty(ex.data.iteration);
errorInfo = [];
rethrowError = [];

try
   cont = checkContinue(p.timeoutDuration*2,promptOptions);
   if cont
      close('all')

      if p.resetData
         %Resets current data. [0,0] is for reference and signal counts
         ex = resetAllData(ex,[0,0]);
      end

      % Changed: the current local experiment state is pushed back to the base
      % workspace after initialization so manual saves no longer see old ex
      % values after an interrupt. -Div
      runHasSavableState = true;
      publishCurrentExperiment(ex);

      %Plots the pulse sequence on the first iteration if desired
      if p.plotPulseSequence
         seq = ex.pulseBlaster.userSequence;
         yax = [];
         xax = 0;
         nBin = sum(~isspace(seq(1).channelsBinary));

         for kk = 1:numel(seq)
            binChannels = seq(kk).channelsBinary;
            binChannels = binChannels(~isspace(binChannels));%Removes spaces from channel binary

            xax = [xax,xax(end)+seq(kk).duration]; %#ok<AGROW>
            for jj = 1:nBin
               yax(kk,jj) = str2double(binChannels(jj))+(nBin-(jj-1))*2+.5; %#ok<SAGROW>
            end
         end

         ySize = size(yax,1);
         for jj = 1:nBin
            yax(ySize+1,jj) = yax(numel(seq),jj); %#ok<SAGROW>
         end

         pulseSequenceFig = figure(51);
         pulseSequenceAxes = axes(pulseSequenceFig);
         stairs(pulseSequenceAxes,xax,yax)
      end

      if startIteration > p.nIterations
         error('Scan not reset and number of iterations complete equals number of iterations desired')
      end

      for ii = startIteration:p.nIterations

         %Reset current scan each iteration
         ex = resetScan(ex);

         % Changed: a partially completed iteration now resumes from the point
         % immediately before the first incomplete scan location instead of
         % skipping to the next iteration. -Div
         if ii == startIteration && hasPartialIteration
            ex.odometer = resumePreviousPoint;
         end

         publishCurrentExperiment(ex);

         %While the odometer is not at its max value
         while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

            %Checks if stage optimization should be done, then does it if so
            [ex,doOptimization] = checkOptimization(ex);
            if doOptimization,  ex = stageOptimization(ex);   end

            %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
            ex = takeNextDataPoint(ex,'pulse sequence');

            %Subtract baseline from ref and sig
            ex = subtractBaseline(ex,p.baselineSubtraction);

            %If using counter, convert counts to counts/s
            if strcmpi(p.collectionType,'counter') && p.perSecond

               %If dataonbuffer isn't 0, actual collection time will be time of data collection/(time of data
               %collection+buffer)
               if isfield(p,'dataOnBuffer') && isfield(p,'collectionDuration') && p.dataOnBuffer ~= 0 && p.collectionDuration ~= 0
                  actualCollectionTime = p.collectionDuration ./ (p.collectionDuration + p.dataOnBuffer);
                  ex = convertToRate(ex,actualCollectionTime);
               else
                  ex = convertToRate(ex);
               end
            end

            %Create matrix where first row is ref, second is sig, and columns indicate iteration
            data = createDataMatrixWithIterations(ex);
            %Find average data across iterations by taking mean across all columns
            averageData = mean(data,2);
            %Current data is last column
            currentData = data(:,end);
            %Gets data points
            dataPoints = ex.data.nPoints(ex.odometer{:},:);

            if isscalar(averageData)
               averageData(2) = 0;
            end
            if isscalar(currentData)
               currentData(2) = 0;
            end
            averageContrast = (averageData(1) - averageData(2)) / averageData(1);
            currentContrast = (currentData(1) - currentData(2)) / currentData(1);

            %Find and plot data with current and average figures

            yAxisLabel = 'Contrast';
            if p.plotAverageContrast
               ex = plotData(ex,averageContrast,'Average Contrast',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end
            if p.plotCurrentContrast
               ex = plotData(ex,currentContrast,'Current Contrast',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end
            if strcmpi(p.collectionType,'analog')
               yAxisLabel = 'Reference (V)';
            elseif strcmpi(p.collectionType,'counter') && p.perSecond
               yAxisLabel = 'Reference (counts/s)';
            else
               yAxisLabel = 'Reference (counts)';
            end
            signalAxisLabel = strrep(yAxisLabel,'Reference','Signal');

            if p.plotAverageReference
               ex = plotData(ex,averageData(1),'Average Reference',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end
            if p.plotCurrentReference
               ex = plotData(ex,currentData(1),'Current Reference',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end
            % Changed: Average/Current Signal now use a signal-specific axis
            % label instead of reusing the reference label. -Div
            if p.plotAverageSignal
               ex = plotData(ex,averageData(2),'Average Signal',signalAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end
            if p.plotCurrentSignal
               ex = plotData(ex,currentData(2),'Current Signal',signalAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end

            yAxisLabel = 'SNR (arbitrary units)';
            if p.plotAverageSNR
               if ~p.invertSignalForSNR
                  SNRVal = sqrt(averageData(1)) * averageContrast;
               else
                  SNRVal = sqrt(averageData(1)) * averageContrast^(-1);
               end
               SNRVal = SNRVal * sqrt(mean(dataPoints,"all"));
               ex = plotData(ex,SNRVal,'Average SNR',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end
            if p.plotCurrentSNR
               if ~p.invertSignalForSNR
                  SNRVal = sqrt(currentData(1)) * currentContrast;
               else
                  SNRVal = sqrt(currentData(1)) * currentContrast^(-1);
               end
               SNRVal = SNRVal * sqrt(dataPoints(ex.data.iteration(ex.odometer{:})));
               ex = plotData(ex,SNRVal,'Current SNR',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end

            yAxisLabel = 'Number of Data Points';
            if p.plotAverageDataPoints
               ex = plotData(ex,mean(dataPoints,"all"),'Average Data Points',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end
            if p.plotCurrentDataPoints
               ex = plotData(ex,dataPoints(ex.data.iteration(ex.odometer{:})),'Current Data Points',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
            end

            %If a new post-optimization value is needed, record current data
            if ex.optimizationInfo.enableOptimization && ex.optimizationInfo.needNewValue
               ex.optimizationInfo.postOptimizationValue = currentData(1);
               ex.optimizationInfo.needNewValue = false;
            end

            % Changed: the most recent completed point is published after every
            % acquisition so Ctrl-C followed by saveData(ex,...) captures the
            % current run instead of stale workspace state. -Div
            publishCurrentExperiment(ex);
         end

         plotLabelInfo = cell(3,2);
         if p.normalizeFFTByMagnet
            plotLabelInfo(1,:) = {'x label','Î³/2Ï€ (MHz/T)'};
         else
            plotLabelInfo(1,:) = {'x label','Frequency (MHz)'};
         end
         plotLabelInfo(2,:) = {'y label','Intensity (a.u.)'};
         if isfield(p,'tauDuration')
            plotLabelInfo(3,:) = {'title',sprintf('Contrast FFT (tau=%d ns)',p.tauDuration)};
         else
            plotLabelInfo(3,:) = {'title',sprintf('Contrast FFT')};
         end
         if p.plotAverageContrastFFT
            [ex,fftOut,frequencyAxis] = dataFourierTransform(ex,1:ii,'contrast',p.normalizeFFTByMagnet);
            frequencyAxis = frequencyAxis * 1e-6;%Conversion to MHz
            storedLabel = plotLabelInfo{3,2};
            plotLabelInfo{3,2} = ['Average ',plotLabelInfo{3,2}];
            ex = plotFullDataSet(ex,'Average Contrast FFT',frequencyAxis,fftOut,plotLabelInfo,p.verticalLineInfo);
            plotLabelInfo{3,2} = storedLabel;
         end
         if p.plotCurrentContrastFFT
            [ex,fftOut,frequencyAxis] = dataFourierTransform(ex,ii,'contrast',p.normalizeFFTByMagnet);
            frequencyAxis = frequencyAxis * 1e-6;%Conversion to MHz
            storedLabel = plotLabelInfo{3,2};
            plotLabelInfo{3,2} = ['Current ',plotLabelInfo{3,2}];
            ex = plotFullDataSet(ex,'Current Contrast FFT',frequencyAxis,fftOut,plotLabelInfo,p.verticalLineInfo);
            plotLabelInfo{3,2} = storedLabel; %#ok<NASGU>
         end

         checkpointCount = checkpointCount + 1;
         if p.autoSaveEveryIteration
            % Changed: runScan now writes one overwrite-in-place checkpoint per
            % completed iteration using the shared snapshot format. -Div
            safeSaveRunSnapshot(ex,saveSettings.baseSavePath,p,...
               'status','checkpoint',...
               'checkpoint',true,...
               'saveAverageContrastPNG',false,...
               'runStartTime',runStartTime,...
               'checkpointCount',checkpointCount);
         end

         if ii ~= p.nIterations
            % Changed: stop and flush the DAQ before every between-iteration prompt.
            % This was added because the diary showed overflow and callback spam while
            % MATLAB was waiting inside checkContinue(). -Div
            ex.DAQ = stopCollection(ex.DAQ,true);
            cont = checkContinue(p.timeoutDuration,promptOptions);
            if ~cont
               runStatus = 'stopped';
               break
            end
            fprintf('Beginning iteration %d\n',ii+1)
         else
            runStatus = 'completed';
         end
      end
   end
catch ME
   % Changed: errors now carry structured save metadata so the final save
   % keeps the failing state and the original MATLAB exception details. -Div
   errorInfo = struct('identifier',ME.identifier,'message',ME.message,'stack',ME.stack);
   rethrowError = ME;
   runStatus = 'error';
end

% Changed: all exit paths now publish the latest experiment, clean up the
% DAQ, and perform a final shared save when there is current run state. -Div
publishCurrentExperiment(ex);
ex.DAQ = stopCollection(ex.DAQ,true);
if runHasSavableState
   safeSaveRunSnapshot(ex,saveSettings.baseSavePath,p,...
      'status',runStatus,...
      'checkpoint',false,...
      'saveAverageContrastPNG',p.saveAverageContrastPNG,...
      'runStartTime',runStartTime,...
      'errorInfo',errorInfo,...
      'checkpointCount',checkpointCount);
end

if ~isempty(rethrowError)
   warning("Error occurred at %s",string(datetime))
   rethrow(rethrowError)
elseif strcmp(runStatus,'completed')
   fprintf('Scan complete\n')
end
end

function [startIteration,hasPartialIteration,resumePreviousPoint,completedIterations] = determineResumeState(ex,p)
if p.resetData || isempty(ex.data) || ~isstruct(ex.data) || ~isfield(ex.data,'iteration') || isempty(ex.data.iteration)
   startIteration = 1;
   hasPartialIteration = false;
   resumePreviousPoint = [];
   completedIterations = 0;
   return
end

iterationMatrix = ex.data.iteration;
completedIterations = min(iterationMatrix(:));
currentIteration = max(iterationMatrix(:));
hasPartialIteration = currentIteration > completedIterations;

if hasPartialIteration
   startIteration = completedIterations + 1;
   [scanOrder,firstIncompleteIndex] = findFirstIncompleteScanPoint(ex,startIteration);
   if isempty(firstIncompleteIndex)
      hasPartialIteration = false;
      startIteration = currentIteration + 1;
      resumePreviousPoint = [];
   elseif firstIncompleteIndex == 1
      resumePreviousPoint = num2cell(ones(1,numel(ex.scan)));
      resumePreviousPoint{end} = 0;
   else
      resumePreviousPoint = scanOrder{firstIncompleteIndex-1};
   end
else
   startIteration = completedIterations + 1;
   resumePreviousPoint = [];
end
end

function [scanOrder,firstIncompleteIndex] = findFirstIncompleteScanPoint(ex,targetIteration)
scanOrder = buildScanOrder([ex.scan.nSteps]);
firstIncompleteIndex = [];

for ii = 1:numel(scanOrder)
   currentPoint = scanOrder{ii};
   if ex.data.iteration(currentPoint{:}) < targetIteration
      firstIncompleteIndex = ii;
      return
   end
end
end

function scanOrder = buildScanOrder(maxValues)
currentPoint = num2cell(ones(1,numel(maxValues)));
currentPoint{end} = 0;
scanOrder = cell(prod(maxValues),1);

for ii = 1:numel(scanOrder)
   currentPoint = experiment.incrementOdometer(currentPoint,maxValues);
   scanOrder{ii} = currentPoint;
end
end

function publishCurrentExperiment(ex)
try
   assignin("base","ex",ex)
catch
end
end

function saveSettings = resolveRunSaveSettings(ex,p)
if isempty(p.saveName)
   baseName = createDefaultRunSaveName(ex);
else
   baseName = char(p.saveName);
end

if isempty(p.saveDirectory)
   saveDirectory = fullfile(fileparts(fileparts(mfilename('fullpath'))),'Saved Data');
else
   saveDirectory = char(p.saveDirectory);
end

if ~isempty(baseName)
   [sentDirectory,sentName,~] = fileparts(baseName);
   if ~isempty(sentName)
      if isempty(sentDirectory)
         baseName = fullfile(saveDirectory,sentName);
      else
         baseName = fullfile(sentDirectory,sentName);
      end
   end
else
   baseName = fullfile(saveDirectory,createDefaultRunSaveName(ex));
end

saveSettings = struct('baseSavePath',baseName);
end

function baseName = createDefaultRunSaveName(ex)
if ~isempty(ex.scan) && isfield(ex.scan(1),'notes') && ~isempty(ex.scan(1).notes)
   baseName = char(ex.scan(1).notes);
else
   baseName = 'ExperimentRun';
end

baseName = regexprep(baseName,'[^A-Za-z0-9_-]+','_');
baseName = regexprep(baseName,'_+','_');
baseName = regexprep(baseName,'^_|_$','');
if isempty(baseName)
   baseName = 'ExperimentRun';
end
baseName = sprintf('%s_%s',baseName,char(datetime('now','Format','yyyyMMdd_HHmmss')));
end

function safeSaveRunSnapshot(ex,saveName,p,varargin)
try
   saveRunSnapshot(ex,saveName,p,varargin{:});
catch ME
   warning('runScan:SaveSnapshotFailed','Failed to save run snapshot: %s',ME.message)
end
% Changed: replaced the final direct stop with shared cleanup so normal completion
% also leaves no stale unread DAQ data behind. -Div
ex.DAQ = stopCollection(ex.DAQ,true);
end
