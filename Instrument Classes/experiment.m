classdef experiment

   properties
      scan %Structure containing info specific to each scan within the broader operation
      odometer %Keeps track of position in scan
      plots
      manualSteps
      useManualSteps = false;%Use steps entered by user rather than evenly spaced
      forcedCollectionPauseTime = .1;%To fully compensate for DAQ and pulse blaster and prevent periodic changes in data collected
      nPointsTolerance = .01;
      maxFailedCollections = 9;
      notifications = false;
      data
      optimizationInfo
      randomizeScanPoints = false;
   end

   properties (Hidden)
      debugging
   end

   properties (Dependent)
      %Specific instruments that are stored within instrumentCells
      %These are purely for the user's benefit to make code more readable,
      %so add to these as desired
      %When adding, make sure to also add set/get functions (second set of
      %methods)
      pulseBlaster
      DAQ
      PIstage
      SRS_RF
      windfreak_RF
      hamm
      DDL
      ndYAG
   end

   properties (SetAccess = protected, GetAccess = public)
      %Read-only
      instrumentIdentifiers
      instrumentClasses
      instrumentCells
   end

   methods

       function h = experiment()
           h.optimizationInfo.enableOptimization = true;
            h.optimizationInfo.algorithmType = 'max value';
            h.optimizationInfo.acquisitionType = 'pulse blaster';
            h.optimizationInfo.stageAxes = [];
            h.optimizationInfo.steps = [];
            h.optimizationInfo.timePerPoint = .1;
            h.optimizationInfo.timeBetweenOptimizations = 120;
            h.optimizationInfo.useTimer = false;
            h.optimizationInfo.percentageToForceOptimization =.75;
            h.optimizationInfo.usePercentageDifference = false;
            h.optimizationInfo.needNewValue = false;
            h.optimizationInfo.lastOptimizationTime = [];
            h.optimizationInfo.maxValueRecord = [];
            h.optimizationInfo.allValuesRecord = {};
            h.optimizationInfo.storeAllValues = false;
            h.optimizationInfo.maxLocationRecord = [];
            h.optimizationInfo.postOptimizationValue = 0;
            h.optimizationInfo.rfStatus = 'off';
            h.optimizationInfo.radius = [];
       end

      function h= takeNextDataPoint(h,acquisitionType)
         %Check if valid configuration (always need PB and DAQ, sometimes
         %needs RF or stage, rarely needs laser)

         %If the odometer is at the max value, end this function without
         %incrementing anything
         if all(cell2mat(h.odometer) == [h.scan.nSteps])
            return
         end

         %Increment odometer to next value
         newOdometer = experiment.incrementOdometer(h.odometer,[h.scan.nSteps]);

         %Determine which scans need to be changed. Scans whose odometer
         %value isn't changed don't need to be set again. Often gets 1
         %value corresponding to the most nested scan being incremented
         needChanging = find(cell2mat(newOdometer) ~= cell2mat(h.odometer));

         %Sets odometer to the incremented value
         h.odometer = newOdometer;

         for ii = needChanging
            %Sets the instrument's parameter to the value determined by
            %the step of the scan
            h = setInstrument(h,ii);
         end

         %Actually takes the data using selected acquisition type
         [h,dataOut,nPoints] = getData(h,acquisitionType);

         %Increments number of data points taken by 1
         h.data.iteration(h.odometer{:}) = h.data.iteration(h.odometer{:}) + 1;

         %Takes data and puts it in the current iteration spot for this
         %data point
         currentIteration = h.data.iteration(h.odometer{:});
         h.data.values{h.odometer{:},currentIteration} = dataOut;
         h.data.nPoints(h.odometer{:},currentIteration) = nPoints;
      end

      function h = setInstrument(h,scanToChange)
         currentScan = h.scan(scanToChange);%Pulls current scan to change
         currentScan.odometer = h.odometer{scanToChange};

         currentScan.identifier = instrumentType.giveProperIdentifier(currentScan.identifier);

         if ~isa(currentScan.bounds,'cell')%Cell indicates multiple new values
            if h.useManualSteps
               newValue = h.manualSteps{scanToChange};
               if currentScan.odometer == 0
                  newValue = newValue(1);
               else
                  newValue = newValue(currentScan.odometer);
               end
            else
               newValue = currentScan.bounds(1) + currentScan.stepSize*(currentScan.odometer-1);%Computes new value
               
            end
         else
             newValue = zeros([numel(currentScan.bounds) 1]);
            for ii = 1:numel(currentScan.bounds)               
               if h.manualSteps
                  %Get the manual steps for the current scan, for
                  %the address dictated by the loop, for the
                  %current step of that scan
                  if currentScan.odometer == 0
                     newValue(ii) = h.manualSteps{scanToChange}{ii}(1);
                  else
                     newValue(ii) = h.manualSteps{scanToChange}{ii}(currentScan.odometer);
                  end
               else
                  newValue(ii) = currentScan.bounds{ii}(1) + currentScan.stepSize(ii)*(currentScan.odometer-1);
               end
            end
         end

         if strcmp(currentScan.identifier,'forcedCollectionPauseTime')
            h.forcedCollectionPauseTime = newValue;
            return
         end

         %Sets instrument to whatever was found above
         relevantInstrument = h.instrumentCells{findInstrument(h,currentScan.identifier)};

         %Does heavy lifting of actually sending commands to instrument
         switch class(relevantInstrument)

            case 'RF_generator'
               switch lower(currentScan.parameter)
                  case 'frequency'
                     relevantInstrument.frequency = newValue;
                  case 'amplitude'
                     relevantInstrument.amplitude = newValue;
               end

            case 'pulse_blaster'
               switch lower(currentScan.parameter)
                  case 'duration'
                     %For each pulse address, modify the duration based on
                     %the new values
                     for ii = 1:numel(currentScan.address)
                        % if h.manualSteps
                        %    %Get the manual steps for the current scan, for
                        %    %the address dictated by the loop, for the
                        %    %current step of that scan
                        %    if h.odometer(scanToChange) == 0
                        %       newValue = h.manualSteps{scanToChange}{ii}(1);
                        %    else
                        %       newValue = h.manualSteps{scanToChange}{ii}(h.odometer(scanToChange));
                        %    end
                        % else
                        %    newValue = currentScan.bounds{ii}(1) + currentScan.stepSize(ii)*(h.odometer(scanToChange));
                        % end
                        relevantInstrument = modifyPulse(relevantInstrument,currentScan.address(ii),'duration',newValue(ii),false);
                     end
                     relevantInstrument = sendToInstrument(relevantInstrument);
                   otherwise
                       error('unknown scan parameter')
               end

            case 'stage'
               if isscalar(newValue) %Only 1 axis
                  relevantInstrument = absoluteMove(relevantInstrument,currentScan.parameter,newValue);
               else %Multiple axes moving simultaneously
                  axisNames = convertStringsToChars(currentScan.parameter);
                  for ii = 1:numel(axisNames)
                     currentAxis = axisNames(ii);
                     relevantInstrument = absoluteMove(relevantInstrument,currentAxis,newValue(ii));
                  end
               end
         end

         %Feeds instrument info back out
         h.instrumentCells{strcmp(h.instrumentIdentifiers,currentScan.identifier)} = relevantInstrument;

      end

      function h = addScans(h,scanInfo)
         %Requires:
         %Scan type (eg. frequency)
         %Class of object scanned (eg. RF_generator)
         %nSteps OR step size for every scan dimension
         %Bounds (start and end)
         %pulse addresses if relevant
         %Optional:
         %Scan label (arbitrary, used for display)

         mustContainField(scanInfo,{'bounds','parameter'})
         if any(cellfun(@isempty,{scanInfo.identifier})) || any(cellfun(@isempty,{scanInfo.parameter}))
            error('All fields must contain non-empty values for each scan')
         end

         %Sets identifier to proper name
         scanInfo.identifier = instrumentType.giveProperIdentifier(scanInfo.identifier);

         %If you are using a manual scan, much of the scan addition process
         %is different
         if h.useManualSteps
            %Computes bounds and number of steps for each scan dimension
            n = cellfun(@numel,h.manualSteps);
            b(:,1) = cellfun(@min,h.manualSteps);
            b(:,2) = cellfun(@max,h.manualSteps);
            for ii = 1:numel(n)
               scanInfo(ii).nSteps = n(ii);
               scanInfo(ii).bounds = b(ii);
            end

            %Sets scan as the current scanInfo
            h.scan = scanInfo;
            return
         end

         if (~isfield(scanInfo,'stepSize') || isempty(scanInfo.stepSize))...
                 && (~isfield(scanInfo,'nSteps') && ~isempty(scanInfo.nSteps))
            error('Scan must contain either stepSize or nSteps field')
         end

         %Note: I don't think matlab likes structs with dimensionality.
         %Most operations I wish to perform need strange workarounds
         %like assigning a variable before taking each element or
         %needing a for loop to assign every element in a field
         %Note on note: I don't remember what I was doing here****
         %          if any(cellfun(@isempty,{scanInfo.stepSize}))
         %             error('All fields must contain non-empty values for each scan')
         %          end
         % if any(cellfun(@isempty,{scanInfo.stepSize}))
         %    error('All fields must contain non-empty values for each scan')
         % end

         b = [scanInfo.bounds];
         if ~isa(b,'cell'),     b = {b};      end

         if isfield(scanInfo,'stepSize') && ~isempty(scanInfo.stepSize)
            s = [scanInfo.stepSize];
            n = cellfun(@(x)abs(x(2)-x(1)),b);

            if isscalar(n)
               n = n(1) ./ s;
            elseif numel(s) == numel(b)
               n = n ./s;
               if any(n~=n(1)) %Check if all nSteps are the same as the first
                  error('Computed number of steps not equivalent for every scan dimension')
               end
               n = n(1);
            else
               error('stepSize must be a scalar with 1 element or a vector with number of elements matching number of elements of bounds')
            end
            n = n+1;%Matlab starts at 1

            scanInfo.nSteps = round(n);
         end

         n = [scanInfo.nSteps];
         if any(n~=n(1)) %Check if all nSteps are the same as the first
            error('Number of steps not equivalent for every scan dimension')
         end
         n = n(1);

         s = cellfun(@(x)x(2)-x(1),b);
         scanInfo.stepSize = s ./ (n-1);

         %Sets scan as the current scanInfo
         if isempty(h.scan)
            h.scan = scanInfo;
         else
            h.scan(end+1) = scanInfo;
         end
      end

      function h = validateExperimentalConfiguration(h)
         %Deprecated function previously checking if correct instruments were connected

         return 
         
      end

      function dataMatrix = createDataMatrixWithIterations(h,varargin)
         %Finds matrix of current and previous iterations for given cell in
         %given data point. 2nd argument is data point (default to odometer
         %reading)
         %Does not support multiple data points
         %Final dimension will be the "iteration" dimension

         %2nd argument is cell corresponding to the specific data point
         %within the scan
         if nargin > 1 && ~isempty(varargin{1})
            dataPoint = num2cell(varargin{1});
         else
            dataPoint = h.odometer;
         end

         currentIteration = h.data.iteration(dataPoint{:});
         if currentIteration == 0
            dataMatrix = nan;
            return
         elseif currentIteration == 1
             dataMatrix = h.data.values{dataPoint{:}}';
             return
         end

         if ~isa(h.data.values,'cell')
             dataMatrix = h.data.values(dataPoint{:},:);
             return
         end

         %Gets the data for all iterations of the current point according to the odometer or optional input          
         currentData = squeeze(h.data.values(dataPoint{:},:));      

         %Deletes all the data points that are empty
         currentData(isempty(currentData)) = [];

         %Used to find dimensionality
         comparisonMatrix = currentData{1};

         if any(size(comparisonMatrix) == 1) %Only happens for a vector

            %Creates 2 dimensional matrix where first dimension is of size
            %of data vector while second dimension is of number of
            %iterations
            dataMatrix = zeros([numel(comparisonMatrix) currentIteration]);

            for ii = 1:numel(currentData)
               dataMatrix(:,ii) = currentData{ii};
            end
            return
         end

         s.type = '()';
         s.subs = cell(1,ndims(comparisonMatrix)+1);

         %Creates n+1 dimensional array where n is the number of dimensions
         %of the data without iterations
         %All dimensions but the last are the same size as their corresponding
         %data and the last is the size of the number of iterations
         dataMatrix = zeros([size(comparisonMatrix) numel(currentData)]);

         %Converts the "cell" dimension into an additional matrix dimension
         for ii = 1:numel(currentData)%For each cell
            s.subs{end} = ii;
            dataMatrix = subsasgn(dataMatrix,s,currentData{ii});
         end
      end

      function h = resetScan(h)
         %Sets the scan to the starting value for each dimension of the
         %scan
         h = getInstrumentNames(h);
         h.odometer = num2cell(ones(1,numel(h.scan)));
         for ii = 1:numel(h.odometer)
            h = setInstrument(h,ii);
         end
         h.odometer{end} = 0;

         %Reset which points are completed for only current plots
         if ~isempty(h.plots)
             plotNames = fieldnames(h.plots);
             isCurrent = contains(lower(plotNames),'current');
             if any(isCurrent)
                 plotNames = plotNames(isCurrent);
                 for ii = 1:numel(plotNames)
                     h.plots.(plotNames{ii}).completedPoints(:) = false;
                 end
             end
         end

      end

      function h = resetAllData(h,resetValue)
         %Resets all stored data within the experiment object

         %Squeeze is necessary to remove first dimension if there is a
         %multi-dimensional scan
         if isscalar(h.scan)
            h.data.iteration = zeros(1,h.scan.nSteps);
         else
            h.data.iteration = zeros([h.scan.nSteps]);
         end

         %Makes cell array of equivalent size to above
         h.data.values = num2cell(h.data.iteration)';

         %This sets every cell to be the value resetValue in the way one
         %might expect the following to do so:
         %h.data.values{:} = resetValue;
         %The above doesn't work due to internal matlab shenanigans but
         %using the deal function is quite helpful
         [h.data.values{:}] = deal(resetValue);

         h.data.nPoints = h.data.iteration';
         h.data.failedPoints = h.data.iteration';

         %Reset which points are completed
         if ~isempty(h.plots)
             plotNames = fieldnames(h.plots);
             for ii = 1:numel(plotNames)
                 h.plots.(plotNames{ii}).completedPoints(:) = false;
             end
         end
      end

      function h = getInstrumentNames(h)
         %For each instrument get the "proper" identifier
         if isempty(h.instrumentCells)
            h.instrumentIdentifiers = [];
            h.instrumentClasses = [];
         else
            h.instrumentIdentifiers = cellfun(@(x)instrumentType.giveProperIdentifier(x.identifier),h.instrumentCells,'UniformOutput',false);
            h.instrumentClasses = cellfun(@(x)class(x),h.instrumentCells,'UniformOutput',false);
         end         
      end

      function h = stageOptimization(h)

         %Steps input should be cell array with number of elements equivalent to number of axes in sequence.axes
         %Each element should be a vector of relative positions that should be tested
         %e.g. {[-1,-.75,-.5,-.25,0,.25,.5,.75,1],[-2,-1.5,-1,-.5,0,.25,.5]} for {'x','y'}

         optInfo = h.optimizationInfo;%shorthand

         optInfo.acquisitionType = experiment.discernExperimentType(optInfo.acquisitionType);

         if strcmp(optInfo.acquisitionType,'none')
            error('Cannot perform stage optimization without acquiring data')
         end
         
         if h.notifications
             nTotalSteps = sum(cellfun(@(x)numel(x),optInfo.steps));
            fprintf('Beginning optimization (%d steps, %.2f seconds per step)\n',nTotalSteps,optInfo.timePerPoint);
         end

         %If using pulse sequence to collect data, change sequence
         if strcmp(optInfo.acquisitionType,'pulse sequence')
            %Store old sequence then delete to clear way for new sequence
            oldSequence = h.pulseBlaster.userSequence;            
            h.pulseBlaster = deleteSequence(h.pulseBlaster);

            %Store old total loop settings then set to no total loop
            oldUseTotalLoop = h.pulseBlaster.useTotalLoop;
            h.pulseBlaster.useTotalLoop = false;

            %Creates sequence depending on RF status
            switch optInfo.rfStatus
               case {'on',true,'sig'}

                  %Basic data collection
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{'AOM','RF'},500,'Initial buffer');
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{'AOM','DAQ','RF'},optInfo.timePerPoint*1e9,'Taking data');

               case {'off',false,'ref'}

                  %Basic data collection
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{'AOM'},500,'Initial buffer');
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{'AOM','DAQ'},optInfo.timePerPoint*1e9,'Taking data');

                case {'contrast','con','snr','signaltonoise','signal to noise','noise'}

                  %ODMR sequence
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{},2500,'Initial buffer');
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{'AOM','DAQ'},(optInfo.timePerPoint*1e9)/2,'Reference');
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{},2500,'Middle buffer signal off');
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{'Signal'},2500,'Middle buffer signal on');
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{'AOM','DAQ','RF','Signal'},(optInfo.timePerPoint*1e9)/2,'Signal');
                  h.pulseBlaster = condensedAddPulse(h.pulseBlaster,{'Signal'},2500,'Final buffer');                  

               otherwise
                  error('RF status (.rfStatus) must be "on", "off", or "contrast"')
            end

            %Send new sequence to instrument
            h.pulseBlaster = sendToInstrument(h.pulseBlaster);
         end

         optInfo.stageAxes = string(optInfo.stageAxes);       

         %Performs stage movement, gets data for each location, then moves to best location along each axis
         for ii = 1:numel(optInfo.stageAxes)

            %Creates empty cell array for storing data
            rawData = cell(1,numel(optInfo.steps{ii}));

            %Gets row of the current axis
            axisRow = strcmpi(h.PIstage.axisSum(:,1),optInfo.stageAxes(ii));
            %Finds absolute axis locations using step info and current location
            stepLocations = optInfo.steps{ii} + h.PIstage.axisSum{axisRow,2};

            for jj = 1:numel(optInfo.steps{ii})
               %Moves to location for taking this data
               h.PIstage = absoluteMove(h.PIstage,optInfo.stageAxes(ii),stepLocations(jj));

               %Get data at this location
               [h,rawData{jj}] = getData(h,optInfo.acquisitionType);
            end

            %After acquiring data, use below algorithms to get single value to fit for each location
            switch optInfo.acquisitionType
               case 'pulse sequence'
                  switch optInfo.rfStatus
                      case {'off','on',true,false,'ref','sig'}
                        dataVector = cellfun(@(x)x(1),rawData,'UniformOutput',false);
                        dataVector = cell2mat(dataVector);
                     case {'con','contrast'}
                        dataVector = cellfun(@(x)(x(1)-x(2))/x(1),rawData,'UniformOutput',false);
                        dataVector = cell2mat(dataVector);
                      case {'snr','signaltonoise','signal to noise','noise'}
                          conVector = cellfun(@(x)(x(1)-x(2))/x(1),rawData,'UniformOutput',false);
                          refVector = cellfun(@(x)x(1),rawData,'UniformOutput',false);
                          conVector = cell2mat(conVector);
                          refVector = cell2mat(refVector);
                          dataVector = conVector .* (refVector .^ (1/2));
                  end
               case 'scmos' %unimplemented
            end
            
            %Use optimization algorithm to get max value and position
            [maxVal,maxPosition] = experiment.optimizationAlgorithm(dataVector,stepLocations,optInfo.algorithmType);

            %Store all values obtained if enabled
            if optInfo.storeAllValues
               h.optimizationInfo.allValuesRecord{ii,end+1} = dataVector;
               %Prevent memory leak by deleting values if past 100,000 elements
               if numel(h.optimizationInfo.allValuesRecord) > 1e5
                  h.optimizationInfo.allValuesRecord(:,1:1e4) = [];
               end
            end

            %Records maximum value and location
           h.optimizationInfo.maxValueRecord(ii,end+1) = maxVal;
           h.optimizationInfo.maxLocationRecord(ii,end+1) = maxPosition;

           %Prevent memory leak by deleting values if past 100,000 elements
           if numel(h.optimizationInfo.maxValueRecord) > 1e5
              h.optimizationInfo.allValuesRecord(:,1:1e4) = [];
              h.optimizationInfo.maxLocationRecord(:,1:1e4) = [];
           end

           %Move to maximum location
            h.PIstage = absoluteMove(h.PIstage,optInfo.stageAxes(ii),maxPosition);
         end

         %Set pulse blaster back to previous sequence
         if strcmpi(optInfo.acquisitionType,'pulse sequence')
            h.pulseBlaster.useTotalLoop = oldUseTotalLoop;
            h.pulseBlaster.userSequence = oldSequence;
            h.pulseBlaster = sendToInstrument(h.pulseBlaster);
         end

         %Set current time as time of last optimization
         h.optimizationInfo.lastOptimizationTime = datetime;
         %Request new postOptimizationValue for comparison
         h.optimizationInfo.needNewValue = true;      

         if h.notifications
            fprintf('Optimization complete\n')
         end

      end

      function [h,performOptimization] = checkOptimization(h)
         %Checks if stage optimization should occur based on time and percentage difference criteria
         %performOptimization is boolean 

         %Required fields and default values
         optimizationDefaults = {'enableOptimization',true;...
            'algorithmType','max value';...
            'acquisitionType','pulse blaster';...
            'stageAxes',[];...
            'steps',[];...
            'timePerPoint',.1;...
            'timeBetweenOptimizations',120;...%0 means run optimization every time
            'useTimer',false;...
            'percentageToForceOptimization',.75;...
            'usePercentageDifference',false;...
            'needNewValue',false;...
            'lastOptimizationTime',[];...
            'maxValueRecord',[];...
            'allValuesRecord',{};...
            'storeAllValues',false;...
            'maxLocationRecord',[];...
            'postOptimizationValue',0;...
            'rfStatus','off';...
            'radius',[]};

         %Checks if fields are present and gives default values
         h.optimizationInfo = mustContainField(h.optimizationInfo,optimizationDefaults(:,1),optimizationDefaults(:,2));

         %Shorthand
         optInfo = h.optimizationInfo;

         totalOn = strcmpi(instrumentType.discernOnOff(optInfo.enableOptimization),'on');
         timerOn = strcmpi(instrumentType.discernOnOff(optInfo.useTimer),'on');
         percentageOn = strcmpi(instrumentType.discernOnOff(optInfo.usePercentageDifference),'on');

         %If optimization as a whole has been disabled, immediately return false
         if ~totalOn
            performOptimization = false;
            return
         end

         %If timer is enabled and time since last optimization is greater than set timeBetweenOptimizations
         %OR
         %If percentage difference is enabled and the current data point is less than postOptimizationValue*percentageToForceOptimization
         if all([h.odometer{:}] == 0) || (timerOn && (isempty(optInfo.lastOptimizationTime) || seconds(datetime - optInfo.lastOptimizationTime) > optInfo.timeBetweenOptimizations)) ...
               || ...
            (percentageOn && (isempty(optInfo.percentageToForceOptimization) || ...
               h.data.values{h.odometer{:},h.data.iteration(h.odometer{:})}(1) < optInfo.postOptimizationValue * optInfo.percentageToForceOptimization))
            performOptimization = true;
         else
            performOptimization = false;
         end
      end

      function [h,dataOut,nPointsTaken] = getData(h,acquisitionType)

         %Gets "correct" name for experiment type
         acquisitionType = experiment.discernExperimentType(acquisitionType);

         %Don't collect data if set to none
         if strcmpi(acquisitionType,'none')
            return
         end

         nPointsTaken = 0;%default to 0
         switch lower(acquisitionType)
            case 'pulse sequence'

               nPauseIncreases = 0;
               originalPauseTime = h.forcedCollectionPauseTime;
               %For slightly changing sequence to get better results
               bufferPulses = findPulses(h.pulseBlaster,'active channels','data','contains') - 1;
               bufferDuration = h.pulseBlaster.userSequence(bufferPulses(1)).duration;

               while true
                  %Reset DAQ in preparation for measurement
                  h.DAQ = resetDAQ(h.DAQ);
                  h.DAQ.takeData = true;

                  pause(h.forcedCollectionPauseTime/2)

                  %Start sequence
                  runSequence(h.pulseBlaster)

                  n = 0;

                  %Wait until pulse blaster says it is done running
                  while pbRunning(h.pulseBlaster)
                      if strcmpi(h.DAQ.continuousCollection,'off')                          
                          n = n+1;
                          if n == 1
                              dataOut = readDAQData(h.DAQ);
                          else
                        dataOut = dataOut + readDAQData(h.DAQ);
                          end
                      else
                          pause(.001)
                      end                     
                  end

                  %Stop sequence. This allows pulse blaster to run the same
                  %sequence again by calling the runSequence function
                  stopSequence(h.pulseBlaster)

                  pause(h.forcedCollectionPauseTime)

                  % Add something for outliers (more than 3 std devs
                  % away) ***********

                  h.DAQ.takeData = false;

                  if strcmpi(h.DAQ.continuousCollection,'off')
                      dataOut = dataOut./n;
                      break
                  end
                  nPointsTaken = h.DAQ.dataPointsTaken;
                  expectedDataPoints = h.pulseBlaster.sequenceDurations.sent.dataNanoseconds;
                  expectedDataPoints = (expectedDataPoints/1e9) * h.DAQ.sampleRate;

                  if nPointsTaken > expectedDataPoints*(1-h.nPointsTolerance) ||...
                          nPointsTaken > expectedDataPoints *(1+h.nPointsTolerance)
                          if ~all(cell2mat(h.odometer) == 0)
                            h.data.failedPoints(h.odometer{:},h.data.iteration(h.odometer{:})+1) = nPauseIncreases;
                          end
                     if nPauseIncreases ~= 0
                        h.forcedCollectionPauseTime = originalPauseTime;
                        for ii = 1:numel(bufferPulses)
                            h.pulseBlaster = modifyPulse(h.pulseBlaster,bufferPulses(ii),'duration',bufferDuration,false);
                        end
                        h.pulseBlaster = sendToInstrument(h.pulseBlaster);
                     end
                     break
                  elseif nPauseIncreases < h.maxFailedCollections
                     nPauseIncreases = nPauseIncreases + 1;
                     if h.notifications
                        warning('Obtained %.4f percent of expected data points\nIncreasing forced pause time temporarily (%d times)',...
                           (100*nPointsTaken)/expectedDataPoints,nPauseIncreases)
                     end
                     h.forcedCollectionPauseTime = h.forcedCollectionPauseTime + originalPauseTime;
                     %Usually hits aom/daq compensation but thats fine
                     for ii = 1:numel(bufferPulses)
                            h.pulseBlaster = modifyPulse(h.pulseBlaster,bufferPulses(ii),'duration',bufferDuration,false);
                     end
                     h.pulseBlaster = sendToInstrument(h.pulseBlaster);
                     pause(.1)%For next data point to come in before discarding the read
                     %Discards any data that might have "carried
                     %over" from the previous data point
                     if h.DAQ.handshake.NumScansAvailable > 0
                        [~] = read(h.DAQ.handshake,h.DAQ.handshake.NumScansAvailable,"OutputFormat","Matrix");
                     end
                  else
                     h.forcedCollectionPauseTime = originalPauseTime;
                     stop(h.DAQ.handshake)
                     error('Failed %d times to obtain correct number of data points. Latest percentage: %.4f',...
                         nPauseIncreases,(100*nPointsTaken)/expectedDataPoints)

                  end

               end

               if strcmpi(h.DAQ.continuousCollection,'on')
                  dataOut(1) = h.DAQ.handshake.UserData.reference;
                  dataOut(2) = h.DAQ.handshake.UserData.signal;
                  %FIX THIS**** Should be dividing by signal data points or
                  %reference data points, not total/2
                  if strcmp(h.DAQ.dataAcquirementMethod,'Voltage')
                     dataOut(1:2) = dataOut(1:2) ./ (h.DAQ.dataPointsTaken/2);
                  end
                  if h.DAQ.handshake.UserData.currentCounts > 3e9
                      printOut(h.DAQ,'Counts nearing max value. Resetting counter')
                      stop(h.DAQ.handshake)
                      resetcounters(h.DAQ.handshake)
                      start(h.DAQ.handshake)
                  end                  
               end
               
            case 'scmos'
               %Takes image and outputs as data

               %Output of takeImage is a cell array for meanImages where each cell is the average image for each set of
               %bounds while frameStacks if a cell array where each cell is a 3D array where each 2D slice is one frame
               %from the camera and each cell corresponds to a different set of bounds

               %Takes image using the camera and the current settings
               [meanImages,frameStacks] = takeImage(h.hamm);

               %First column of cell array is the mean images
               %Second column is the frame stacks
               dataOut = meanImages;
               if ~isempty(frameStacks)
                  dataOut(:,2) = frameStacks;
               end

               %If only one output (mean image with 1 set of bounds), convert output to matrix
               if isscalar(dataOut)
                  dataOut = dataOut{1};
               end

               %List number of points taken as frames per trigger
               nPointsTaken = h.hamm.framesPerTrigger;
         end
      end

      function h = plotData(h,dataIn,plotName,varargin)
         %4th argument is y axis label if desired
         %5th argument is selecting which set of bounds to use if multiple are present (defaults to first)
         %6th argument is boolean to flip scan axes (1st scan made y, 2nd made x)
         %7th argument is update location. Defaults to current odometer location
         %8th argument is x offset
         %Expects matrix of numbers, no cell or strings etc.
         %Does not work for 2D scans using manual steps

         %Prevents errors in variable name by swapping space with
         %underscore
         plotTitle = plotName;
         plotName(plotName==' ') = '_';

         %Creates a figure if one does not already exist
         if ~isfield(h.plots,plotName) ||  ~isfield(h.plots.(plotName),'figure') || ~ishandle(h.plots.(plotName).figure)
            h.plots.(plotName).figure = figure('Name',plotTitle,'NumberTitle','off');
         end

         %Creates axes if one does not already exist
         if ~isfield(h.plots.(plotName),'axes') || ~isvalid(h.plots.(plotName).axes)
            h.plots.(plotName).axes = axes(h.plots.(plotName).figure);
         end

         %If there is already some kind of data displayed (line or image)
         if ~isfield(h.plots.(plotName),'dataDisplay') || ~isvalid(h.plots.(plotName).dataDisplay)
            replot = true;
         else
            replot = false;
         end

         %Check for 1D vs 2D
         %Find where CData is different and replace

         if isscalar(h.scan) %1D data

            %If multiple sets of bounds, choose first or based on 5th argument
            if isa(h.scan.bounds,'cell') && ~h.useManualSteps
               if nargin >= 5 && ~isempty(varargin{2}) && isscalar(varargin{2})
                  xBounds = h.scan.bounds{varargin{2}};
                  stepSize = h.scan.stepSize(varargin{2});
               else
                  xBounds = h.scan.bounds{1};
                  stepSize = h.scan.stepSize{1};
               end
            elseif ~h.useManualSteps
               xBounds = h.scan.bounds;
               stepSize = h.scan.stepSize;
            end

            %Adds x offset to bounds if given as argument
            if nargin >= 8 && ~isempty(varargin{5})
               xBounds = xBounds + varargin{5};
            end       
            
            %x axis isn't the same. Assumed to be different plot entirely
               if (~isfield(h.plots,plotName) || ~isfield(h.plots.(plotName),'axes') || ~isfield(h.plots.(plotName),'dataDisplay'))||...
                       (~isvalid(h.plots.(plotName).axes) || ~isvalid(h.plots.(plotName).dataDisplay)) ||...
                       (~h.useManualSteps && any(h.plots.(plotName).axes.XLim ~= xBounds) ||...
                       (~h.useManualSteps && numel(h.plots.(plotName).dataDisplay.YData) ~= h.scan.nSteps))  || ...
                     (h.useManualSteps && h.plots.(plotName).dataDisplay.XData ~= h.manualSteps)
                  replot = true;
               end

               if replot
                  %Creates x axis from manual steps or from scan settings
                  if h.useManualSteps
                     xAxis = h.manualSteps;
                  else
                     xAxis = xBounds(1):stepSize:xBounds(2);
                  end

                  emptyData = zeros(1,h.scan.nSteps);

                  %Creates the actual plot as a line
                  h.plots.(plotName).dataDisplay = plot(h.plots.(plotName).axes,xAxis,emptyData);

                  %Add x and, optionally, y labels
                  xlabel(h.plots.(plotName).axes,h.scan.parameter)
                  if nargin >= 4 && ~isempty(varargin{1})
                     ylabel(h.plots.(plotName).axes,varargin{1})
                  end
                  title(h.plots.(plotName).axes,[plotTitle,', ',h.scan.notes])           
               
                  h.plots.(plotName).axes.XLim = xBounds;

                  h.plots.(plotName).completedPoints = boolean(zeros(1,h.scan.nSteps));
               end               

               %Change current data point value
               h.plots.(plotName).dataDisplay.YData(h.odometer{1}) = dataIn;   

               %Set current data point to being completed
               h.plots.(plotName).completedPoints(h.odometer{1}) = true;

               %Replace value of all incomplete data points
               completePoints = h.plots.(plotName).completedPoints;
               if ~all(completePoints)
                   meanVal = mean(h.plots.(plotName).dataDisplay.YData(completePoints));
                   stdVal = std(h.plots.(plotName).dataDisplay.YData(completePoints));
                   h.plots.(plotName).dataDisplay.YData(~completePoints) = meanVal-(stdVal*3);
               end

               return
         end

         %For 2D data

         if h.useManualSteps
            error('plotData function does not work for 2D data using manual steps')
         end

         for ii = 1:2
            %Gets bounds and step size for both scans
            if isa(h.scan(ii).bounds,'cell')
               if nargin >= 5 && ~isempty(varargin{2}) && isscalar(varargin{2})
                  imageBounds{ii} = h.scan(ii).bounds{varargin{2}}; %#ok<*AGROW>
                  stepSize(ii) = h.scan(ii).stepSize{varargin{2}};
                  nSteps(ii) = h.scan(ii).nSteps{varargin{2}};
               else
                  imageBounds{ii} = h.scan(ii).bounds{1};
                  stepSize(ii) = h.scan(ii).stepSize{1};
                  nSteps(ii) = h.scan(ii).nSteps{1};
               end
            else
               imageBounds{ii} = h.scan(ii).bounds;
               stepSize(ii) = h.scan(ii).stepSize;
               nSteps(ii) = h.scan(ii).nSteps;
            end
            params{ii} = h.scan(ii).parameter;
         end

         %Flip scan order (make scan 2 x and scan 1 y)
         if nargin >= 6 && ~isempty(varargin{3}) && varargin{3}
            imageBounds = flip(imageBounds);
            stepSize = flip(stepSize);
            nSteps = flip(nSteps);
            params = flip(params);
         end         
         
         if ~replot && (any(h.plots.(plotName).dataDisplay.XData ~= imageBounds{2}) || any(h.plots.(plotName).dataDisplay.YData ~= imageBounds{1}))
            replot = true;
         end

         if replot
            emptyImage = zeros(nSteps(1),nSteps(2));
            h.plots.(plotName).dataDisplay = imagesc(h.plots.(plotName).axes,emptyImage);
            % axis(h.plots.(plotName).axes,'square')%Makes pixel size square, not stretched out
            % h.plots.(plotName).axes.Colormap = cmap2gray(h.plots.(plotName).axes.Colormap);
            h.plots.(plotName).colorbar = colorbar(h.plots.(plotName).axes);
            xlabel(h.plots.(plotName).axes,params{2})
            ylabel(h.plots.(plotName).axes,params{1})
            title(h.plots.(plotName).axes,[plotTitle,' - ', h.scan(1).notes])
            h.plots.(plotName).dataDisplay.XData = imageBounds{2};
            h.plots.(plotName).dataDisplay.YData = imageBounds{1};
            h.plots.(plotName).axes.XLim = imageBounds{2};
            h.plots.(plotName).axes.YLim = imageBounds{1};
            h.plots.(plotName).axes.YDir = 'reverse';
            %The following makes the image look nicer, otherwise it cuts the edge points in half
            h.plots.(plotName).axes.XLim(2) = h.plots.(plotName).axes.XLim(2) + stepSize(2)/2;
            h.plots.(plotName).axes.XLim(1) = h.plots.(plotName).axes.XLim(1) - stepSize(2)/2;
            h.plots.(plotName).axes.YLim(2) = h.plots.(plotName).axes.YLim(2) + stepSize(1)/2;
            h.plots.(plotName).axes.YLim(1) = h.plots.(plotName).axes.YLim(1) - stepSize(1)/2;           
            
            for ii = 1:numel(h.scan)
                stepList(ii) = h.scan(ii).nSteps;
            end
            h.plots.(plotName).completedPoints = boolean(stepList);
            if isfield(h.plots.(plotName),'minValue')
                h.plots.(plotName) = rmfield(h.plots.(plotName),'minValue');
                h.plots.(plotName) = rmfield(h.plots.(plotName),'maxValue');
            end
         end

         %Adds data for current odometer location
         h.plots.(plotName).dataDisplay.CData(h.odometer{:}) = dataIn;

         %Set current data point to being completed
         h.plots.(plotName).completedPoints(h.odometer{:}) = true;

         if ~isfield(h.plots.(plotName),'minValue')
             h.plots.(plotName).minValue = dataIn;
             h.plots.(plotName).maxValue = dataIn+1;
         else
             if dataIn < h.plots.(plotName).minValue
                 h.plots.(plotName).minValue = dataIn;
             end
             if dataIn > h.plots.(plotName).maxValue
                 h.plots.(plotName).maxValue = dataIn;
             end
         end

         h.plots.(plotName).axes.CLim = [h.plots.(plotName).minValue h.plots.(plotName).maxValue];
      end

%       function h = plotFFT(h,iterations)

%           nPoints = numel(nonzeros(ex.data.iteration));
%           if nPoints > 3 %Can't properly do fft if less than 4 points
%               fftData = zeros(nPoints,1);
%               for jj = 1:nPoints
%                   currData = createDataMatrixWithIterations(ex,jj);
%                   fftData(jj) = (currData(1) - currData(2))/currData(1);
%               end
%               [fftOut,frequencyAxis] = fourierTransform(fftData,ex.scan.stepSize(p.boundsToUse));
%           end
%       end

      function h = saveData(h,saveName)
         %Saves data to file as well as relevant info
         %UNIMPLEMENTED: save images to tif files

         %Check if any data exists
         if isempty(h.data)
            error('No data to save')
         end

         %Empty struct that will contain relevant information
         dataInfo = {};
         n = 0;

         %Adds RF info
         if ~isempty(h.SRS_RF)
            n = n+1;
            dataInfo{n,1} = 'RF frequency';
            dataInfo{n,2} = h.SRS_RF.frequency;
            n = n+1;
            dataInfo{n,1} = 'RF amplitude';
            dataInfo{n,2} = h.SRS_RF.amplitude;
         end

         %Adds pulse sequence
         if ~isempty(h.pulseBlaster)
            n = n+1;
            dataInfo{n,1} = 'Pulse sequence';
            dataInfo{n,2} = h.pulseBlaster.sequenceSentToPulseBlaster;
            n = n+1;
            dataInfo{n,1} = 'Number of loops for pulse sequence';
            dataInfo{n,2} = h.pulseBlaster.nTotalLoops;
         end

         %Adds camera info
         if ~isempty(h.hamm)
            n = n+1;
            dataInfo{n,1} = 'Frames per trigger';
            dataInfo{n,2} = h.hamm.framesPerTrigger;
            n = n+1;
            dataInfo{n,1} = 'Exposure time';
            dataInfo{n,2} = h.hamm.exposureTime;
         end

         %Adds scan info
         if ~isempty(h.scan)
            n = n+1;
            dataInfo{n,1} = 'Scan info';
            dataInfo{n,2} = h.scan;
         end

         %Saves data along with found info
         dataToSave = h.data;
         save(saveName,"dataToSave","dataInfo")

      end

      function h = overlapAlgorithm(h,algorithmType,params)
         %Runs one of the overlap algorithms to get stage in position for
         %SM experiment

         %Does not alter bounds of image taken

         mustContainField(params,{'nFrames','exposureTime','highPass','gaussianRatio'})

         %Change image settings to take desired image, to revert
         %settings once finished
         oldInfo.framesPerTrigger = h.hamm.framesPerTrigger;
         h.hamm.framesPerTrigger = params.nFrames;
         oldInfo.outputFullImage = h.hamm.outputFullImage;
         h.hamm.outputFullImage = false;
         oldInfo.outputFrameStack = h.hamm.outputFrameStack;
         h.hamm.outputFrameStack = false;
         oldInfo.exposureTime = h.hamm.exposureTime;
         h.hamm.exposureTime = params.exposureTime;

         switch lower(algorithmType)
            %Algorithm 1:
            %Move stage negative on both axes to get clear separation
            %between peaks
            %Take a long-averaged image
            %Use the conversion between pixels and nm to tell the stage how
            %far to move
            case {'average and convert','convert','precision','average'}
               %Checks to see if params have required fields
               mustContainField(params,{'separationDistance','nFrames','exposureTime',...
                  'highPass','gaussianRatio','micronToPixel'})

               %Move negative on both x and y to create clearly separated
               %gaussian spots. Direction of later movement will always be
               %positive to counteract this
               h = relativeMove(h.PIstage,'x',-params.separationDistance);
               h = relativeMove(h.PIstage,'y',-params.separationDistance);

               %Takes image used to determine distance
               im = takeImage(h.hamm);

               %Gets position estimate using 1D gaussian fits for each axis
               %(see function)
               [xEst,yEst] = experiment.double1DGaussian(im,params.highPass,params.gaussianRatio);

               %Convert to microns
               xEst = xEst/params.micronToPixel;
               yEst = yEst/params.micronToPixel;

               %Move the stage to the estimate for x and y
               h = relativeMove(h.PIstage,'x',xEst);
               h = relativeMove(h.PIstage,'y',yEst);


            case {'double linear','linear','convergence'}
               %Algorithm 2:
               %Gaussian fit of data to get location of 2 peaks (done along x
               %and along y)

               mustContainField(params,{'nFrames','exposureTime','highPass','gaussianRatio',...
                  'axisSequence','nSteps','radius','maxAttempts'})

               %First radius is x, second radius is y

               nSteps = params.nSteps;
               r = params.radius;

               if numel(params.radius) ~= 2
                  error('radius must contain 2 values, the first representing the x radius and the second the y radius')
               end

               %Calculate step size for both x and y
               stepIncrements = params.radius ./ params.nSteps;

               distanceEstimates = zeros(nSteps,2);
               for ii = 1:params.nSteps %x and y

                  if ii == 1
                     %For the first step, move x and y by negative radius input
                     h.PIstage = relativeMove(h.PIstage,'x',-r(1));
                     h.PIstage = relativeMove(h.PIstage,'y',-r(2));
                  else
                     %Increment step of x and y
                     h.PIstage = relativeMove(h.PIstage,'x',stepIncrements(1));
                     h.PIstage = relativeMove(h.PIstage,'y',stepIncrements(2));
                  end

                  %Takes image used to estimate location
                  im = takeImage(h.hamm);

                  %Finds estimates for x and y based on collapsed 1-D gaussians
                  [distanceEstimates(ii,1),distanceEstimates(ii,2)] = experiment.double1DGaussian(im,params.highPass,params.gaussianRatio);
               end

               for ii = 1:2
                  %x or y distances
                  distances = distanceEstimates(:,ii);

                  %Creates axis along which distance between gaussian peaks will be plotted
                  movementAxis = 1:params.nSteps;

                  %Deletes all distances (and corresponding points on movement axis) that were unable to be found
                  movementAxis(distances == 0) = [];
                  distances(distances == 0) = [];

                  if numel(distances) < 2
                     error('Not enough data points found to perform fit. Increase radius, nSteps, and/or gaussianRatio')
                  end

                  %Creates linear fit of remaining data
                  linFit = polyfit(movementAxis',distances',1);

                  %Finds x intercept of fit, corresponding to estimate of location of greatest overlap
                  estimatedIntercept = -linFit(2)/linFit(1);
                  estimatedIntercept = estimatedIntercept*stepIncrements(ii);

                  %Moves stage to location of estimated intercept
                  if ii == 1
                     h.PIstage = relativeMove(h.PIstage,'x',estimatedIntercept-params.radius(ii));
                  else
                     h.PIstage = relativeMove(h.PIstage,'y',estimatedIntercept-params.radius(ii));
                  end

               end
         end

         %Sets camera settings back to prior status
         h.hamm.framesPerTrigger = oldInfo.framesPerTrigger;
         h.hamm.outputFullImage = oldInfo.outputFullImage;
         h.hamm.outputFrameStack = oldInfo.outputFrameStack;
         h.hamm.exposureTime = oldInfo.exposureTime;

      end

      function [h,outlierArray] = findDataOutliers(h,varargin)
         %Second input is for what parameter to test (default number of data points)
         %Third input is number of standard deviations away from mean to be considered an outlier (default 3)
         %Fourth is for manual input for dataset
         %Assumes final dimension is the "iteration" dimension

         if nargin < 2 || isempty(varargin{1})
            outlierParameter = 'npoints';
         end

         if nargin < 3 ||  isempty(varargin{2})
            outlierThreshold = 3;
         end

         switch (outlierParameter)
            case 'npoints'
               dataset = h.data.nPoints;
            case 'contrast'
               dataset = cellfun(@(x)(x(1)-x(2))/x(1),h.data.values,'UniformOutput',false);
            case 'reference'
               dataset = cellfun(@(x)x(1),h.data.values,'UniformOutput',false);
         end

         if nargin > 3 && ~isempty(varargin{3})
            dataset = varargin{3};
         end

         outlierArray = isoutlier(dataset,"mean","ThresholdFactor",outlierThreshold,ndims(dataset));

      end

      function h = subtractBaseline(h,baseline)
         %Subtracts baseline value from all data within current scan value

         h.data.values{h.odometer{:},h.data.iteration(h.odometer{:})} = h.data.values{h.odometer{:},h.data.iteration(h.odometer{:})} - baseline;
      end

      function h = convertToRate(h,varargin)
         %Divides current value by half the time, in seconds, of the data collection for sequence sent to pulse blaster
         %Half the time because half is for reference, half for signal

         %If custom ratio of data time is given, multiple found data time by that
         dataTime = h.pulseBlaster.sequenceDurations.sent.dataNanoseconds/2;
         if nargin > 1
            dataTime = dataTime .* varargin{1};
         end

         h.data.values{h.odometer{:},h.data.iteration(h.odometer{:})} = h.data.values{h.odometer{:},h.data.iteration(h.odometer{:})}...
            ./ (dataTime * 1e-9);
      end
   end

   methods
      %Set/Get for instruments

      %General function for get/set of instruments
      function objectMatch = findInstrument(h,identifierInput)
         %Finds the location within instrumentCells for a given instrument

         %Ensures up to date list of instruments
         h = getInstrumentNames(h);

         %Obtain proper identifier for the input and compare with instruments present
         properIdentifier = instrumentType.giveProperIdentifier(identifierInput);
         objectMatch = strcmp(h.instrumentIdentifiers,properIdentifier);

         if sum(objectMatch) > 2
            error('More than 1 instrument with identifier %s present')
         end

      end

      function s = getInstrumentVal(h,instrumentName)
         instrumentLocation = findInstrument(h,instrumentName);
         if ~any(instrumentLocation)
            s = [];
         else
            s = h.instrumentCells{instrumentLocation};
         end
      end

      function h = setInstrumentVal(h,instrumentName,val)
         instrumentLocation = findInstrument(h,instrumentName);
         if sum(instrumentLocation) == 0
            if ~any(strcmp({'RF_generator','stage','pulse_blaster','laser','kinesis_piezo','deformable_mirror','DAQ_controller','cam'},class(val)))
               error('Cannot set %s as it does not exist',instrumentName)
            end
            h.instrumentCells{end+1} = val;
         else
            h.instrumentCells{instrumentLocation} = val;
         end
      end

      %Specific instruments. Add/Remove as needed to correspond to
      %dependent variables
      function s = get.pulseBlaster(h)
         s = getInstrumentVal(h,'pulse blaster');
      end
      function h = set.pulseBlaster(h,val)
         h = setInstrumentVal(h,'pulse blaster',val);
      end

      function s = get.PIstage(h)
         s = getInstrumentVal(h,'stage');
      end
      function h = set.PIstage(h,val)
         h = setInstrumentVal(h,'stage',val);
      end

      function s = get.SRS_RF(h)
         s = getInstrumentVal(h,'srs');
      end
      function h = set.SRS_RF(h,val)
         h = setInstrumentVal(h,'srs',val);
      end

      function s = get.windfreak_RF(h)
         s = getInstrumentVal(h,'wf');
      end
      function h = set.windfreak_RF(h,val)
         h = setInstrumentVal(h,'wf',val);
      end

      function s = get.DAQ(h)
         s = getInstrumentVal(h,'daq');
      end
      function h = set.DAQ(h,val)
         h = setInstrumentVal(h,'daq',val);
      end

      function s = get.DDL(h)
         s = getInstrumentVal(h,'ddl');
      end
      function h = set.DDL(h,val)
         h = setInstrumentVal(h,'ddl',val);
      end

      function s = get.hamm(h)
         s = getInstrumentVal(h,'hamamatsu');
      end
      function h = set.hamm(h,val)
         h = setInstrumentVal(h,'hamamatsu',val);
      end

      function s = get.ndYAG(h)
         s = getInstrumentVal(h,'ndYAG');
      end
      function h = set.ndYAG(h,val)
         h = setInstrumentVal(h,'ndYAG',val);
      end
   end

   methods (Static)
      function [maxValue,maxPosition] = optimizationAlgorithm(dataVector,positionVector,algorithmType)
         %Runs whatever algorithm to find where stage should move

         switch lower(algorithmType)
            case 'max value'
               maxValue = max(dataVector,[],'all');
               maxPosition = positionVector(dataVector == maxValue);

               %If there are more than 1 that are the same value, take the
               %one that is the closest to the median of positions given
               if numel(maxPosition) > 1
                  absDistance = abs(positionVector - median(positionVector));
                  %Get minimum only of values that correspond to the max
                  %value
                  minDistance = min(absDistance(dataVector == maxValue),[],'all');
                  maxPosition = positionVector(absDistance == minDistance);
               end
            case 'gaussian'

         end



      end

      function newValues = incrementOdometer(oldValues,maxValues)
         oldValues = cell2mat(oldValues);
         if all(oldValues == maxValues)
            error('Odometer overflow. Attempted to increment value beyond maximum for all scans')
         end

         newValues = oldValues;
         %Begin at most nested scan
         amountNested = numel(newValues);
         while true

            %This shouldn't happen. If every scan has hit its maximum, the
            %amount nested will become 0 (this loop would try to change the
            %0th scan which doesn't exist in matlab). In this case, the
            %function should end with an
            if amountNested == 0
               error('Odometer overflow. Attempted to increment value beyond maximum for all scans')
            end

            %Increment the current scan
            newValues(amountNested) = newValues(amountNested) + 1;

            %If there is overflow of current scan i.e. it went over its
            %maximum
            if newValues(amountNested) > maxValues(amountNested)
               %Reset current scan
               newValues(amountNested) = 1;
               %Decrease the nesting amount to the next "largest" scan
               amountNested = amountNested - 1;
            else
               %If it was within the max value, no need to change other
               %scan values
               break
            end
         end
         %Odometer should be in form of a cell instead of matrix since this is how matlab can use it as an index
         newValues = num2cell(newValues);
      end

      function [xEst,yEst] = double1DGaussian(im,percentileCutoff,cutoffForGaussianAmplitudeRatio,varargin)
         %Gets rid of all data below a certain percentile to remove any
         %confounding data
         cutoffNumber = prctile(im,percentileCutoff,'all');
         cutoffIm = im;
         cutoffIm(cutoffIm < cutoffNumber) = 0;

         %Repeat this process for summing along the rows vs summing
         %along the columns
         for ii = ["rowSum","colSum"]
            %Checks, if 4th argument is given, whether it contains rowSum
            %and colSum to skip it if it doesn't
            if nargin > 3 && ~contains(varargin{1},ii)
               if ii=="rowSum"
                  xEst = 0;
               elseif ii=="colSum"
                  yEst = 0;
               end
               continue
            end
            %Takes the sum along all rows
            if ii == "rowSum"
               vectorSummed = sum(cutoffIm,1);
               xax = 1:size(cutoffIm,2);
            else
               vectorSummed = sum(cutoffIm,2);
               xax = 1:size(cutoffIm,1);
            end

            %Fits the 1D data using a double gaussian then pulls the
            %resulting coefficients
            doubleGauss = fit(xax.',vectorSummed.','gauss2');
            currentCoeffs = coeffvalues(doubleGauss);

            %If one peak is some magnitude larger than the other it is very
            %likely that the peaks are overlapped to the point of being
            %indistinguishable
            if currentCoeffs(1)*cutoffForGaussianAmplitudeRatio > currentCoeffs(4) && currentCoeffs(1) < currentCoeffs(4)*cutoffForGaussianAmplitudeRatio
               est = abs(currentCoeffs(2)-currentCoeffs(5));
            else
               est = 0;
            end

            if ii == "rowSum"
               xEst = est;
            else
               yEst = est;
            end
         end
      end

      function formalName = discernExperimentType(userInput)
         switch userInput
            case {'pulse sequence','sequence','pulses','daq','pulse blaster','pb'}
               formalName = 'pulse sequence';
            case {'scmos','cam','camera'}
               formalName = 'scmos';
            case {'none',''}
               formalName = 'none'; %no data collection
            otherwise
               error('Invalid experiment type. Must be "pulse sequence" or "scmos"')
         end
      end

   end
end
