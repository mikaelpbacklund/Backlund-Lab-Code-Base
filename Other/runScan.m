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
   'resetData',true};

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

%Sends information to command window
if p.resetData
    iterationsForInfo = p.nIterations;
else
    iterationsForInfo = p.nIterations - size(ex.data.values,2);
end
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,iterationsForInfo,.28)

cont = checkContinue(p.timeoutDuration*2);
if ~cont
   return
end

try

    close('all')

    if p.resetData
       %Resets current data. [0,0] is for reference and signal counts
       ex = resetAllData(ex,[0,0]);
    end

%Plots the pulse sequence on the first iteration if desired
if p.plotPulseSequence
   seq = ex.pulseBlaster.userSequence;
   xax = [];
   yax = [];
   for kk = 1:numel(seq)
      binChannels = seq(kk).channelsBinary;
      binChannels = binChannels(~isspace(binChannels));%Removes spaces from channel binary
      nBin = numel(binChannels);
      if kk == 1
         xax = 0;
         for jj = 1:nBin
            yax(kk,jj) = (nBin-(jj-1))*2+.5; %#ok<*SAGROW>
         end
      else
         xax = [xax,xax(end)+seq(kk-1).duration]; %#ok<*AGROW>
         for jj = 1:numel(binChannels)
            yax(kk,jj) = str2double(binChannels(jj))+(nBin-(jj-1))*2+.5; %#ok<*SAGROW>
         end
      end
   end
   pulseSequenceFig = figure(51);
   pulseSequenceAxes = axes(pulseSequenceFig);
   for jj = 1:numel(binChannels)
      stairs(pulseSequenceAxes,xax,yax)
   end
end

if p.resetData
   startIteration = 1;
else
   startIteration = size(ex.data.values,2)+1;
   if startIteration > p.nIterations
      error('Scan not reset and number of iterations complete equals number of iterations desired')
   end
end

for ii = startIteration:p.nIterations

   %Reset current scan each iteration
   ex = resetScan(ex);

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

      if p.plotAverageReference
         ex = plotData(ex,averageData(1),'Average Reference',yAxisLabel,p.boundsToUse,[],[],p.xOffset); 
      end
      if p.plotCurrentReference
         ex = plotData(ex,currentData(1),'Current Reference',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
      end
      if p.plotAverageSignal
         ex = plotData(ex,averageData(2),'Average Signal',yAxisLabel,p.boundsToUse,[],[],p.xOffset); 
      end
      if p.plotCurrentSignal
         ex = plotData(ex,currentData(2),'Current Signal',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
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
   end

   plotLabelInfo = cell(3,2);
   if p.normalizeFFTByMagnet
      plotLabelInfo(1,:) = {'x label','γ/2π (MHz/T)'};
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

   if ii ~= p.nIterations
       cont = checkContinue(p.timeoutDuration);
       if ~cont
           break
       end
       fprintf('Beginning iteration %d\n',ii+1)
   end
end
fprintf('Scan complete\n')
catch ME   
    assignin("base","ex",ex)
    stop(ex.DAQ.handshake)
    warning("Error occurred at %s",string(datetime))
    rethrow(ME)
end
stop(ex.DAQ.handshake)
end