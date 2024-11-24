function ex = runScan(ex,p)
%Runs scan using experiment object
%p is parameter object

mustContainField(p,'collectionType')

paramsWithDefaults = {'plotAverageContrast',true;...
   'plotAverageReference',true;...
   'plotCurrentContrast',true;...
   'plotCurrentReference',true;...
   'baselineSubtraction',0;...
   'boundsToUse',1};

mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2))

try

%Resets current data. [0,0] is for reference and signal counts
ex = resetAllData(ex,[0,0]);

for ii = 1:nIterations

   %Reset current scan each iteration
   ex = resetScan(ex);

   %While the odometer is not at its max value
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps

      %Checks if stage optimization should be done, then does it if so
      if checkOptimization(ex),  ex = stageOptimization(ex);   end

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'pulse sequence');

      %Subtract baseline from ref and sig
      ex = subtractBaseline(ex,p.baselineSubtraction);

      %If using counter, convert counts to counts/s
      if strcmpi(collectionType,'counter')
         ex = convertToRate(ex);
      end

      %Create matrix where first row is ref, second is sig, and columns indicate iteration
      data = createDataMatrixWithIterations(ex);
      %Find average data across iterations by taking mean across all columns
      averageData = mean(data,2);
      %Current data is last column
      currentData = data(:,end);

      %Find and plot reference or contrast
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
      else
         yAxisLabel = 'Reference (counts/s)';
      end
      if p.plotAverageReference
         ex = plotData(ex,averageData(1),'Average Reference',yAxisLabel,p.boundsToUse); 
      end
      if p.plotCurrentReference
         ex = plotData(ex,currentData(1),'Current Reference',yAxisLabel,p.boundsToUse);
      end

      %If a new post-optimization value is needed, record current data
      if ex.optimizationInfo.needNewValue
         ex.optimizationInfo.postOptimizationValue = currentData(1);
         ex.optimizationInfo.needNewValue = false;
      end
     
   end

   if ii ~= nIterations
       cont = checkContinue(timeoutDuration);
       if ~cont
           break
       end
   end
end
fprintf('Scan complete\n')
catch ME   
    stop(ex.DAQ.handshake)
    rethrow(ME)
end
stop(ex.DAQ.handshake)
end