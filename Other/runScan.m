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
   'plotCurrentPercentageDataPoints',false;...
   'plotAveragePercentageDataPoints',false;...
   'invertSignalForSNR',false;...
   'baselineSubtraction',0;...
   'boundsToUse',1;...
   'perSecond',true;...
   'nIterations',1};

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
         ex = convertToRate(ex);
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
         ex = plotData(ex,averageContrast,'Average Contrast',yAxisLabel,p.boundsToUse);
      end
      if p.plotCurrentContrast
         currentContrast = (currentData(1) - currentData(2)) / currentData(1);
         ex = plotData(ex,currentContrast,'Current Contrast',yAxisLabel,p.boundsToUse);
      end
      if strcmpi(p.collectionType,'analog')
         yAxisLabel = 'Reference (V)';
      elseif strcmpi(p.collectionType,'counter') && p.perSecond
         yAxisLabel = 'Reference (counts/s)';
      else
          yAxisLabel = 'Reference (counts)';
      end
      if p.plotAverageReference
         ex = plotData(ex,averageData(1),'Average Reference',yAxisLabel,p.boundsToUse); 
      end
      if p.plotCurrentReference
         ex = plotData(ex,currentData(1),'Current Reference',yAxisLabel,p.boundsToUse);
      end
      ex = plotData(ex,averageData(2),'Average Signal',yAxisLabel,p.boundsToUse); 
      ex = plotData(ex,currentData(2),'Current Signal',yAxisLabel,p.boundsToUse);
      yAxisLabel = 'SNR (arbitrary units)';
      if p.plotAverageSNR
          if strcmpi(p.collectionType,'analog')
              SNRVal = averageData(1) * sqrt(mean(dataPoints,"all"));
          else
              SNRVal = sqrt(averageData(1));
          end
          if ~p.invertSignalForSNR
              SNRVal = SNRVal * ((averageData(1) - averageData(2)) / averageData(1));
          else
              SNRVal = SNRVal * ((averageData(1) - averageData(2)) / averageData(1))^(-1);
          end
         ex = plotData(ex,SNRVal,'Average SNR',yAxisLabel,p.boundsToUse); 
      end
      if p.plotCurrentSNR          
          if strcmpi(p.collectionType,'analog')
              SNRVal = currentData(1) * sqrt(dataPoints(ex.data.iteration(ex.odometer{:})));
          else
              SNRVal = sqrt(currentData(1));
          end
          if ~p.invertSignalForSNR
              SNRVal = SNRVal * ((currentData(1) - currentData(2)) / currentData(1));
              else
              SNRVal = SNRVal * ((currentData(1) - currentData(2)) / currentData(1))^(-1);
          end
         ex = plotData(ex,SNRVal,'Current SNR',yAxisLabel,p.boundsToUse);
      end
      yAxisLabel = 'Number of Data Points';
      if p.plotAveragePercentageDataPoints
         ex = plotData(ex,mean(dataPoints,"all"),'Average Data Points',yAxisLabel,p.boundsToUse); 
      end
      if p.plotCurrentPercentageDataPoints
         ex = plotData(ex,dataPoints(ex.data.iteration(ex.odometer{:})),'Current Data Points',yAxisLabel,p.boundsToUse);
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