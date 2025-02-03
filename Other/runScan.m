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
   'plotPulseSequence',false;...
   'invertSignalForSNR',false;...
   'baselineSubtraction',0;...
   'boundsToUse',1;...
   'perSecond',true;...
   'nIterations',1;...
   'xOffset',0};

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

try

    close('all')

%Resets current data. [0,0] is for reference and signal counts
ex = resetAllData(ex,[0,0]);

for ii = 1:p.nIterations

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

      %Find and plot data with current and average figures

      yAxisLabel = 'Contrast';
      if p.plotAverageContrast
         averageContrast = (averageData(1) - averageData(2)) / averageData(1);
         ex = plotData(ex,averageContrast,'Average Contrast',yAxisLabel,p.boundsToUse,[],[],p.xOffset);
      end
      if p.plotCurrentContrast
         currentContrast = (currentData(1) - currentData(2)) / currentData(1);
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
              SNRVal = sqrt(averageData(1)) * ((averageData(1) - averageData(2)) / averageData(1));
          else
              SNRVal = sqrt(averageData(1)) * ((averageData(1) - averageData(2)) / averageData(1))^(-1);
          end
          SNRVal = SNRVal * sqrt(mean(dataPoints,"all"));
         ex = plotData(ex,SNRVal,'Average SNR',yAxisLabel,p.boundsToUse,[],[],p.xOffset); 
      end
      if p.plotCurrentSNR
          if ~p.invertSignalForSNR
              SNRVal = sqrt(currentData(1)) * ((currentData(1) - currentData(2)) / currentData(1));
              else
              SNRVal = sqrt(currentData(1)) * ((currentData(1) - currentData(2)) / currentData(1))^(-1);
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

      %Plots the pulse sequence on the first iteration if desired
      if p.plotPulseSequence && ii == 1 && cell2mat(ex.odometer) == ones(1,numel(ex.odometer))
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
         pulseSequenceAxes = axes(pulseSequenceFig); %#ok<LAXES>
         for jj = 1:numel(binChannels)
            stairs(pulseSequenceAxes,xax,yax)
         end
      end

      %If a new post-optimization value is needed, record current data
      if ex.optimizationInfo.enableOptimization && ex.optimizationInfo.needNewValue
         ex.optimizationInfo.postOptimizationValue = currentData(1);
         ex.optimizationInfo.needNewValue = false;
      end
     
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