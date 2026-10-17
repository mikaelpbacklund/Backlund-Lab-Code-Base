function ex = runScan(ex,p)
%Runs scan using experiment object
%p is parameter object

warning('off','daq:Session:FlushedAcquiredData')
warning('off','instrument:interface:FlushedData')

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
   'closeFigsEveryIteration',false;...
   'plotEveryNIterations',1};

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

%Sends information to command window
if p.resetData
    iterationsForInfo = p.nIterations;
else
    iterationsForInfo = p.nIterations - size(ex.data.values,2);
end
scanStartInfo(prod([ex.scan.nSteps]),ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,iterationsForInfo,.5)

if ~checkUserInput(ex,p);   return;   end

try
    close('all')

    %Resets current data. [0,0] is for reference and signal counts
    if p.resetData;      ex = resetAllData(ex,[0,0]);    end

%Plots the pulse sequence on the first iteration if desired
if p.plotPulseSequence;   ex = plotPulseSequence(ex);  end

if p.resetData
   startIteration = 1;
else
   startIteration = size(ex.data.values,2)+1;
   if startIteration > p.nIterations
      error('Scan not reset and number of iterations complete equals number of iterations desired')
   end
end

for iterationNumber = startIteration:p.nIterations

   %Reset current scan each iteration
   ex = resetScan(ex);

   %Set samples to reset data point based on expected samples per data toggle on
    if ex.asynchronousCollection
        if p.pollInterval > 5
            warning("Poll interval for DAQ collection should not be greater than 5 seconds. Setting to 5")
            p.pollInterval = 5;
        end
        secondsPerLoop = ex.pulseBlaster.sequenceDurations.user.totalSeconds ./ ex.pulseBlaster.nTotalLoops;
        samplesPerLoop = ex.DAQ.handshake.Rate .*  secondsPerLoop;
        if ex.pulseBlaster.sequenceDurations.user.dataFraction > .1
            ex.DAQ.samplesToReset = samplesPerLoop.*2;
        else
            %Low amount of data collection per loop
            ex.DAQ.samplesToReset = samplesPerLoop.*10;
        end
       ex.storedOdometer = {};
       startDAQ(ex.DAQ);
   end

   %While the odometer is not at its max value
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

      %Checks if stage optimization should be done, then does it if so
      [ex,doOptimization] = checkOptimization(ex);
      if doOptimization
          ex = stageOptimization(ex);
          fprintf('Stage optimized to %.1f x, %.1f y, %.1f z\n',ex.PIstage.axisSum{1,2},ex.PIstage.axisSum{2,2},ex.PIstage.axisSum{3,2})
      end

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'pulse sequence');

      if ex.asynchronousCollection
           %Checks for any new data from the DAQ
           ex = checkAsynchronousData(ex);

           %For each new point, finish it based on parameters then plot
           while numel(ex.freshPoints) ~= 0
              ex = finishAndPlot(ex,p,ex.freshPoints{1},iterationNumber);
              ex.freshPoints(1) = [];
           end
      else
         %Plot new point
         ex = finishAndPlot(ex,p,ex.odometer,iterationNumber);
      end
   end

   if ex.asynchronousCollection
       %Wait for all data to come in
       n = 0;
       while ~isempty(ex.storedOdometer)
           n = n+1;
           % pullAndProcess(ex.DAQ)%Forces pull regardless of timer
           %Checks for any new data from the DAQ
           ex = checkAsynchronousData(ex);

           %For each new point, finish it based on parameters then plot
           while numel(ex.freshPoints) ~= 0
              ex = finishAndPlot(ex,p,ex.freshPoints{1},iterationNumber);
              ex.freshPoints(1) = [];
           end

           pause(.05)
           if n > ((p.pollInterval/.05)*2)
               warning('Not all data points matched')
               break
           end
       end
       stopDAQ(ex.DAQ);       
   end   

   %Plot fourier transforms
   ex = plotFTs(ex,p);

   %Save current iteration data
   ex = saveData(ex);

   if iterationNumber ~= p.nIterations
       
       if ~checkUserInput(ex,p);     break;       end

       if p.closeFigsEveryIteration
           close('all')
           ex.plots = [];
           pause(.1)%give time to reclaim ram
       end
       
       fprintf('Beginning iteration %d\n',iterationNumber+1)
   elseif ~ex.asynchronousCollection
       %Turn off collection once it is finished
       ex.DAQ.continuousCollection = false;
       resetDAQ(ex.DAQ);
   end
end

fprintf('Scan complete\n')
catch ME   
    assignin("base","ex",ex)
    
    if ex.asynchronousCollection
    stopDAQ(ex.DAQ);
    else
        stop(ex.DAQ.handshake)
    end
    warning("Error occurred at %s",string(datetime))
    rethrow(ME)
end
stop(ex.DAQ.handshake)

   function ex = finishAndPlot(ex,p,pointLocation,iterationNumber)

              ex = subtractBaseline(ex,p.baselineSubtraction,pointLocation);

              %If using counter, convert counts to counts/s
              if strcmpi(p.collectionType,'counter') && p.perSecond
                 %If dataonbuffer isn't 0, actual collection time will be time of data collection/(time of data
                 %collection+buffer)
                 if isfield(p,'dataOnBuffer') && isfield(p,'collectionDuration') && p.dataOnBuffer ~= 0 && p.collectionDuration ~= 0
                    actualCollectionTime = p.collectionDuration ./ (p.collectionDuration + p.dataOnBuffer);
                    ex = convertToRate(ex,actualCollectionTime,pointLocation);
                 else
                    ex = convertToRate(ex,[],pointLocation);
                 end
              end

              %Cease plotting if not designated iteration to do so
              if iterationNumber~= 1 && mod(iterationNumber,p.plotEveryNIterations) ~= 0
                  return
              end

              ex = plotAll(ex,p,pointLocation);
   end

   function ex = plotPulseSequence(ex)
      seq = ex.pulseBlaster.userSequence;
      yax = [];
      xax = 0;
      nBin = sum(~isspace(seq(1).channelsBinary));

      for kk = 1:numel(seq)
         binChannels = seq(kk).channelsBinary;
         binChannels = binChannels(~isspace(binChannels));%Removes spaces from channel binary

         xax = [xax,xax(end)+seq(kk).duration]; %#ok<*AGROW>
         for jj = 1:nBin
            yax(kk,jj) = str2double(binChannels(jj))+(nBin-(jj-1))*2+.5; %#ok<*SAGROW>
         end
      end

      ySize = size(yax,1);
      for jj = 1:nBin
         yax(ySize+1,jj) = yax(numel(seq),jj); %#ok<*SAGROW>
      end

      pulseSequenceFig = figure(51);
      pulseSequenceAxes = axes(pulseSequenceFig);
      stairs(pulseSequenceAxes,xax,yax)
   end

   function ex = plotFTs(ex,p,iterationNumber)

      if ~p.plotAverageContrastFFT && ~p.plotCurrentContrastFFT
         return
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
         [ex,fftOut,frequencyAxis] = dataFourierTransform(ex,1:iterationNumber,'contrast',p.normalizeFFTByMagnet);
         frequencyAxis = frequencyAxis * 1e-6;%Conversion to MHz
         storedLabel = plotLabelInfo{3,2};
         plotLabelInfo{3,2} = ['Average ',plotLabelInfo{3,2}];
         ex = plotFullDataSet(ex,'Average Contrast FFT',frequencyAxis,fftOut,plotLabelInfo,p.verticalLineInfo);
         plotLabelInfo{3,2} = storedLabel;
      end
      if p.plotCurrentContrastFFT
         [ex,fftOut,frequencyAxis] = dataFourierTransform(ex,iterationNumber,'contrast',p.normalizeFFTByMagnet);
         frequencyAxis = frequencyAxis * 1e-6;%Conversion to MHz
         storedLabel = plotLabelInfo{3,2};
         plotLabelInfo{3,2} = ['Current ',plotLabelInfo{3,2}];
         ex = plotFullDataSet(ex,'Current Contrast FFT',frequencyAxis,fftOut,plotLabelInfo,p.verticalLineInfo);
         plotLabelInfo{3,2} = storedLabel; %#ok<NASGU>
      end
   end

   function shouldContinue = checkUserInput(ex,p)
      %Asks user whether scan should start
      %Turns off collection from DAQ if relevant
      if ~ex.asynchronousCollection
         ex.DAQ.continuousCollection = false;
         resetDAQ(ex.DAQ);
      end

      %Asks user whether scan should start
      shouldContinue = checkContinue(p.timeoutDuration*2);

      %If should not continue, do not restart DAQ
      if ~shouldContinue;         return;      end
      if ~ex.asynchronousCollection
         ex.DAQ.continuousCollection = true;
         resetDAQ(ex.DAQ);
      end
   end
end
