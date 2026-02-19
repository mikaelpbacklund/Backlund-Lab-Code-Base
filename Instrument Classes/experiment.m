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

      function obj = takeNextDataPoint(obj,acquisitionType)
         %Check if valid configuration (always need PB and DAQ, sometimes
         %needs RF or stage, rarely needs laser)

         %If the odometer is at the max value, end this function without
         %incrementing anything
         if all(cell2mat(obj.odometer) == [obj.scan.nSteps])
            return
         end

         %Increment odometer to next value
         newOdometer = experiment.incrementOdometer(obj.odometer,[obj.scan.nSteps]);

         %Determine which scans need to be changed. Scans whose odometer
         %value isn't changed don't need to be set again. Often gets 1
         %value corresponding to the most nested scan being incremented
         needChanging = find(cell2mat(newOdometer) ~= cell2mat(obj.odometer));

         %Sets odometer to the incremented value
         obj.odometer = newOdometer;

         for ii = needChanging
            %Sets the instrument's parameter to the value determined by
            %the step of the scan
            obj = setInstrument(obj,ii);
         end

         %Actually takes the data using selected acquisition type
         [obj,dataOut,nPoints] = getData(obj,acquisitionType);

         %Increments number of data points taken by 1
         obj.data.iteration(obj.odometer{:}) = obj.data.iteration(obj.odometer{:}) + 1;

         %Takes data and puts it in the current iteration spot for this
         %data point
         currentIteration = obj.data.iteration(obj.odometer{:});
         obj.data.values{obj.odometer{:},currentIteration} = dataOut;
         obj.data.nPoints(obj.odometer{:},currentIteration) = nPoints;
      end

      function obj = setInstrument(obj,scanToChange)
         currentScan = obj.scan(scanToChange);%Pulls current scan to change
         currentScan.odometer = obj.odometer{scanToChange};

         currentScan.identifier = instrumentType.giveProperIdentifier(currentScan.identifier);

         if ~isa(currentScan.bounds,'cell')%Cell indicates multiple new values
            if obj.useManualSteps
               newValue = obj.manualSteps{scanToChange};
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
               if obj.manualSteps
                  %Get the manual steps for the current scan, for
                  %the address dictated by the loop, for the
                  %current step of that scan
                  if currentScan.odometer == 0
                     newValue(ii) = obj.manualSteps{scanToChange}{ii}(1);
                  else
                     newValue(ii) = obj.manualSteps{scanToChange}{ii}(currentScan.odometer);
                  end
               else
                  newValue(ii) = currentScan.bounds{ii}(1) + currentScan.stepSize(ii)*(currentScan.odometer-1);
               end
            end
         end

         if strcmp(currentScan.identifier,'forcedCollectionPauseTime')
            obj.forcedCollectionPauseTime = newValue;
            return
         end

         %Sets instrument to whatever was found above
         relevantInstrument = obj.instrumentCells{findInstrument(obj,currentScan.identifier)};

         %Does heavy lifting of actually sending commands to instrument
         switch class(relevantInstrument)

            case 'RF_generator'
               switch lower(currentScan.parameter)
                  case {'frequency','freq','f'}
                     relevantInstrument.frequency = newValue;
                  case {'amplitude','amp','a'}
                     relevantInstrument.amplitude = newValue;
               end

            case 'pulse_blaster'
               switch lower(currentScan.parameter)
                  case {'duration','dur'}
                     %For each pulse address, modify the duration based on
                     %the new values
                     assignin("base","currentScan",currentScan)
                     for ii = 1:numel(currentScan.address)
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

            case 'laser'
                switch lower(currentScan.parameter)
                   case {'set power','setpower'}
                      relevantInstrument.setPower = newValue;
                   otherwise
                      error('Only setPower can be used as parameter for laser scan')
                end
         end

         %Feeds instrument info back out
         obj.instrumentCells{strcmp(obj.instrumentIdentifiers,currentScan.identifier)} = relevantInstrument;

      end

      function obj = addScans(obj,scanInfo)
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
         if obj.useManualSteps
            %Computes bounds and number of steps for each scan dimension
            n = cellfun(@numel,obj.manualSteps);
            b(:,1) = cellfun(@min,obj.manualSteps);
            b(:,2) = cellfun(@max,obj.manualSteps);
            for ii = 1:numel(n)
               scanInfo(ii).nSteps = n(ii);
               scanInfo(ii).bounds = b(ii);
            end

            %Sets scan as the current scanInfo
            obj.scan = scanInfo;
            return
         end

         if (~isfield(scanInfo,'stepSize') || isempty(scanInfo.stepSize))...
                 && (~isfield(scanInfo,'nSteps') && ~isempty(scanInfo.nSteps))
            error('Scan must contain either stepSize or nSteps field')
         end

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

         %Adds defaults to any fields not already present
         if ~isempty(obj.scan)
            scanInfo = mustContainField(scanInfo,fieldnames(obj.scan),struct2cell(obj.scan(1)));
         end

         %Sets scan as the current scanInfo
         if isempty(obj.scan)
            obj.scan = scanInfo;
         else
            obj.scan(end+1) = scanInfo;
         end

         %Deletes empty scan if there are more than 1
         if all(cellfun(@(x)isempty(x),struct2cell(obj.scan(1)))) && numel(obj.scan)>1
             obj.scan(1) = [];
         end
      end

      function obj = validateExperimentalConfiguration(obj)
         %Deprecated function previously checking if correct instruments were connected

         return 
         
      end

      function dataMatrix = createDataMatrixWithIterations(obj,varargin)
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
            dataPoint = obj.odometer;
         end

         currentIteration = obj.data.iteration(dataPoint{:});
         if currentIteration == 0
            dataMatrix = nan;
            return
         elseif currentIteration == 1
             dataMatrix = obj.data.values{dataPoint{:}}';
             return
         end

         if ~isa(obj.data.values,'cell')
             dataMatrix = obj.data.values(dataPoint{:},:);
             return
         end

         %Gets the data for all iterations of the current point according to the odometer or optional input          
         currentData = squeeze(obj.data.values(dataPoint{:},:));      

         %Deletes all the data points that are empty
         currentData(cellfun(@isempty, currentData)) = [];
         if isempty(currentData)
            dataMatrix = nan;
            return
         end

         %Used to find dimensionality
         comparisonMatrix = currentData{1};

         if isvector(comparisonMatrix)
            %Creates 2 dimensional matrix where first dimension is of size
            %of data vector while second dimension is of number of
            %iterations
            dataMatrix = cell2mat(cellfun(@(x)x',currentData,'UniformOutput',false));
            return
         end

         %Creates n+1 dimensional array where n is the number of dimensions
         %of the data without iterations
         %All dimensions but the last are the same size as their corresponding
         %data and the last is the size of the number of iterations
         dataMatrix = cat(ndims(comparisonMatrix)+1, currentData{:});
      end

      function obj = resetScan(obj)
         %Sets the scan to the starting value for each dimension of the
         %scan
         obj = getInstrumentNames(obj);
         obj.odometer = num2cell(ones(1,numel(obj.scan)));
         for ii = 1:numel(obj.odometer)
            obj = setInstrument(obj,ii);
         end
         obj.odometer{end} = 0;

         %Reset which points are completed for only current plots
         if ~isempty(obj.plots)
             plotNames = fieldnames(obj.plots);
             isCurrent = contains(lower(plotNames),'current');
             if any(isCurrent)
                 plotNames = plotNames(isCurrent);
                 for ii = 1:numel(plotNames)
                     obj.plots.(plotNames{ii}).completedPoints(:) = false;
                 end
             end
         end

      end

      function obj = resetAllData(obj,resetValue)
         %Resets all stored data within the experiment object

         %Squeeze is necessary to remove first dimension if there is a
         %multi-dimensional scan
         if isscalar(obj.scan)
            obj.data.iteration = zeros(1,obj.scan.nSteps);
         else
            obj.data.iteration = zeros([obj.scan.nSteps]);
         end

         %Makes cell array of equivalent size to above
         obj.data.values = num2cell(obj.data.iteration);

         if isscalar(obj.scan)
             obj.data.values = obj.data.values';
         end

         %This sets every cell to be the value resetValue in the way one
         %might expect the following to do so:
         %obj.data.values{:} = resetValue;
         %The above doesn't work due to internal matlab shenanigans but
         %using the deal function is quite helpful
         [obj.data.values{:}] = deal(resetValue);

         obj.data.nPoints = obj.data.iteration;
         obj.data.failedPoints = obj.data.iteration;

         %Reset which points are completed
         if ~isempty(obj.plots)
             plotNames = fieldnames(obj.plots);
             for ii = 1:numel(plotNames)
                 obj.plots.(plotNames{ii}).completedPoints(:) = false;
             end
         end
      end

      function obj = getInstrumentNames(obj)
         %For each instrument get the "proper" identifier
         if isempty(obj.instrumentCells)
            obj.instrumentIdentifiers = [];
            obj.instrumentClasses = [];
            disp('deleted identifiers')
         else
            obj.instrumentIdentifiers = cellfun(@(x)instrumentType.giveProperIdentifier(x.identifier),obj.instrumentCells,'UniformOutput',false);
            obj.instrumentClasses = cellfun(@(x)class(x),obj.instrumentCells,'UniformOutput',false);
            % disp(numel(obj.instrumentIdentifiers))
         end
      end

      function obj = stageOptimization(obj)

         %Steps input should be cell array with number of elements equivalent to number of axes in sequence.axes
         %Each element should be a vector of relative positions that should be tested
         %e.g. {[-1,-.75,-.5,-.25,0,.25,.5,.75,1],[-2,-1.5,-1,-.5,0,.25,.5]} for {'x','y'}

         optInfo = obj.optimizationInfo;%shorthand

         optInfo.acquisitionType = experiment.discernExperimentType(optInfo.acquisitionType);

         if strcmp(optInfo.acquisitionType,'none')
            error('Cannot perform stage optimization without acquiring data')
         end
         
         if obj.notifications
             nTotalSteps = sum(cellfun(@(x)numel(x),optInfo.steps));
            fprintf('Beginning optimization (%d steps, %.2f seconds per step)\n',nTotalSteps,optInfo.timePerPoint);
         end

         %If using pulse sequence to collect data, change sequence
         if strcmp(optInfo.acquisitionType,'pulse sequence')
            %Store old sequence then delete to clear way for new sequence
            oldSequence = obj.pulseBlaster.userSequence;            
            obj.pulseBlaster = deleteSequence(obj.pulseBlaster);

            %Store old total loop settings then set to no total loop
            oldUseTotalLoop = obj.pulseBlaster.useTotalLoop;
            obj.pulseBlaster.useTotalLoop = false;

            % Generate and send pulse sequence using helper
            obj.pulseBlaster = obj.createOptimizationSequence(optInfo);
         end

         optInfo.stageAxes = string(optInfo.stageAxes);       

         %Performs stage movement, gets data for each location, then moves to best location along each axis
         for ii = 1:numel(optInfo.stageAxes)

            axisName = optInfo.stageAxes(ii);
            axisRow = strcmpi(obj.PIstage.axisSum(:,1),axisName);
            stepLocations = optInfo.steps{ii} + obj.PIstage.axisSum{axisRow,2};

            % Initial scan and optimization
            [maxVal,maxPosition,rawData] = obj.optimizationScan(stepLocations, axisName, optInfo.acquisitionType, optInfo.rfStatus, optInfo.algorithmType);

            % Check if movement is more than 25% of the total range
            currentPosition = obj.PIstage.axisSum{axisRow,2};
            movementSize = abs(maxPosition - currentPosition);
            scanRange = max(stepLocations) - min(stepLocations);
            
            if movementSize > 0.25 * scanRange
                if obj.notifications
                    fprintf('Large movement detected (%.2f%% of range). Performing verification scan...\n', ...
                        (movementSize/scanRange)*100);
                end
                
                % Move to the suggested position
                obj.PIstage = absoluteMove(obj.PIstage,axisName,maxPosition);
                
                % Create verification scan around this position with 25% of original range
                verificationRange = scanRange * 0.25;
                verificationSteps = linspace(maxPosition - verificationRange/2, ...
                    maxPosition + verificationRange/2, ...
                    ceil(numel(optInfo.steps{ii})/2)); % Use half the number of original steps
                
                % Verification scan and optimization
                [verificationMaxVal,verificationMaxPosition,~] = obj.optimizationScan(verificationSteps, axisName, optInfo.acquisitionType, optInfo.rfStatus, optInfo.algorithmType);
                
                % Compare results
                if abs(verificationMaxVal - maxVal)/maxVal > 0.2 % If values differ by more than 20%
                    if obj.notifications
                        warning('Verification scan shows significant value difference. Keeping original position for safety.');
                    end
                elseif abs(verificationMaxPosition - maxPosition) > 0.1 * scanRange % If positions differ by more than 10% of range
                    if obj.notifications
                        warning('Verification scan shows different optimal position. Keeping original position for safety.');
                    end
                elseif obj.notifications
                    fprintf('Verification scan confirms original result.\n');
                    maxVal = verificationMaxVal;
                    maxPosition = verificationMaxPosition;
                end
            end

            %Store all values obtained if enabled
            if optInfo.storeAllValues
               obj.optimizationInfo.allValuesRecord{ii,end+1} = rawData;
               %Prevent memory leak by deleting values if past 100,000 elements
               if numel(obj.optimizationInfo.allValuesRecord) > 1e5
                  obj.optimizationInfo.allValuesRecord(:,1:1e4) = [];
               end
            end

            %Records maximum value and location
           obj.optimizationInfo.maxValueRecord(ii,end+1) = maxVal;
           obj.optimizationInfo.maxLocationRecord(ii,end+1) = maxPosition;

           %Prevent memory leak by deleting values if past 100,000 elements
           if numel(obj.optimizationInfo.maxValueRecord) > 1e5
              obj.optimizationInfo.allValuesRecord(:,1:1e4) = [];
              obj.optimizationInfo.maxLocationRecord(:,1:1e4) = [];
           end

           %Move to maximum location
            obj.PIstage = absoluteMove(obj.PIstage,axisName,maxPosition);
         end

         %Set pulse blaster back to previous sequence
         if strcmpi(optInfo.acquisitionType,'pulse sequence')
            obj.pulseBlaster.useTotalLoop = oldUseTotalLoop;
            obj.pulseBlaster.userSequence = oldSequence;
            obj.pulseBlaster = sendToInstrument(obj.pulseBlaster);
         end

         %Set current time as time of last optimization
         obj.optimizationInfo.lastOptimizationTime = datetime;
         %Request new postOptimizationValue for comparison
         obj.optimizationInfo.needNewValue = true;      

         if obj.notifications
            fprintf('Optimization complete\n')
         end

      end

      function pulseBlaster = createOptimizationSequence(obj, optInfo)
         % Helper to generate and send the pulse sequence for stage optimization
         switch optInfo.rfStatus
            case {'on',true,'sig'}
               %Basic data collection
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{'AOM','RF'},500,'Initial buffer');
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{'AOM','DAQ','RF'},optInfo.timePerPoint*1e9,'Taking data');
            case {'off',false,'ref'}
               %Basic data collection
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{'AOM'},500,'Initial buffer');
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{'AOM','DAQ'},optInfo.timePerPoint*1e9,'Taking data');
            case {'contrast','con','snr','signaltonoise','signal to noise','noise'}
               %ODMR sequence
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{},2500,'Initial buffer');
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{'AOM','DAQ'},(optInfo.timePerPoint*1e9)/2,'Reference');
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{},2500,'Middle buffer signal off');
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{'Signal'},2500,'Middle buffer signal on');
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{'AOM','DAQ','RF','Signal'},(optInfo.timePerPoint*1e9)/2,'Signal');
               obj.pulseBlaster = condensedAddPulse(obj.pulseBlaster,{'Signal'},2500,'Final buffer');                  
            otherwise
               error('RF status (.rfStatus) must be "on", "off", or "contrast"')
         end
         pulseBlaster = sendToInstrument(obj.pulseBlaster);
      end

      function [optVal,optPos,rawDataOut] = optimizationScan(obj, stepLocs, axisName, acquisitionType, rfStatus, algorithmType)
         % Moves stage, collects data, processes, and optimizes for given step locations
         rawDataOut = cell(1,numel(stepLocs));
         for jj = 1:numel(stepLocs)
            obj.PIstage = absoluteMove(obj.PIstage, axisName, stepLocs(jj));
            [obj,rawDataOut{jj}] = getData(obj,acquisitionType);
         end
         dataVec = experiment.processOptimizationData(rawDataOut, acquisitionType, rfStatus);
         [optVal,optPos] = experiment.optimizationAlgorithm(dataVec, stepLocs, algorithmType);
      end

      % Helper function to process optimization data
      function processedData = processOptimizationData(rawData, acquisitionType, rfStatus)
         %Processes raw data from stage optimization scans into a vector for optimization
         %Input: rawData - cell array of data points
         %       acquisitionType - type of acquisition ('pulse sequence' or 'scmos')
         %       rfStatus - RF status for pulse sequence data ('on', 'off', 'contrast', etc.)
         %Output: processedData - vector of processed values ready for optimization

         switch acquisitionType
            case 'pulse sequence'
               switch rfStatus
                  case {'off','on',true,false,'ref','sig'}
                     processedData = cellfun(@(x)x(1),rawData,'UniformOutput',false);
                     processedData = cell2mat(processedData);
                  case {'con','contrast'}
                     processedData = cellfun(@(x)(x(1)-x(2))/x(1),rawData,'UniformOutput',false);
                     processedData = cell2mat(processedData);
                  case {'snr','signaltonoise','signal to noise','noise'}
                     conVector = cellfun(@(x)(x(1)-x(2))/x(1),rawData,'UniformOutput',false);
                     refVector = cellfun(@(x)x(1),rawData,'UniformOutput',false);
                     conVector = cell2mat(conVector);
                     refVector = cell2mat(refVector);
                     processedData = conVector .* (refVector .^ (1/2));
               end
            case 'scmos' %unimplemented
               processedData = [];
         end
      end

      function [obj,performOptimization] = checkOptimization(obj)
         %Checks if stage optimization should occur based on time and percentage difference criteria
         %performOptimization is boolean 

         %Required fields and default values
         optimizationDefaults = {'enableOptimization',false;...
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
         obj.optimizationInfo = mustContainField(obj.optimizationInfo,optimizationDefaults(:,1),optimizationDefaults(:,2));

         %Shorthand
         optInfo = obj.optimizationInfo;

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
         if all([obj.odometer{:}] == 0) || (timerOn && (isempty(optInfo.lastOptimizationTime) || seconds(datetime - optInfo.lastOptimizationTime) > optInfo.timeBetweenOptimizations)) ...
               || ...
            (percentageOn && (isempty(optInfo.percentageToForceOptimization) || ...
               obj.data.values{obj.odometer{:},obj.data.iteration(obj.odometer{:})}(1) < optInfo.postOptimizationValue * optInfo.percentageToForceOptimization))
            performOptimization = true;
         else
            performOptimization = false;
         end
      end

      function [obj,dataOut,nPointsTaken] = getData(obj,acquisitionType)
         %Gets "correct" name for experiment type
         acquisitionType = experiment.discernExperimentType(acquisitionType);

         %Don't collect data if set to none
         if strcmpi(acquisitionType,'none')
            return
         end

         nPointsTaken = 0;%default to 0
         switch lower(acquisitionType)
            case 'pulse sequence'
               [obj,dataOut,nPointsTaken] = getPulseSequenceData(obj);
            case 'scmos'
               [obj,dataOut,nPointsTaken] = getSCMOSData(obj);
         end
      end

      function [obj,dataOut,nPointsTaken] = getPulseSequenceData(obj)
         % Helper method for pulse sequence data acquisition
         nPauseIncreases = 0;
         originalPauseTime = obj.forcedCollectionPauseTime;
         dataOut = [];
         nPointsTaken = 0;

         %Stops pulse blaster execution upon forced close
         cleanupObj = onCleanup(@() stopSequence(obj.pulseBlaster));

         %For slightly changing sequence to get better results
         bufferPulses = findPulses(obj.pulseBlaster,'notes','intermission','contains');
         if numel(bufferPulses) > 0
            bufferDuration = obj.pulseBlaster.userSequence(bufferPulses(1)).duration;
         end

         while true
            %Reset DAQ in preparation for measurement
            obj.DAQ = resetDAQ(obj.DAQ);
            obj.DAQ.takeData = true;

            pause(obj.forcedCollectionPauseTime/2)

            %Start sequence
            runSequence(obj.pulseBlaster)

            n = 0;
            %Perform check prior to repeated while loop
            contCollection = strcmpi(obj.DAQ.continuousCollection,'off');

            %Wait until pulse blaster says it is done running
            while pbRunning(obj.pulseBlaster)
               if contCollection                        
                  n = n+1;
                  if n == 1
                     dataOut = readDAQData(obj.DAQ);
                  else
                     dataOut = dataOut + readDAQData(obj.DAQ);
                  end
               else
                  pause(.001)
               end                     
            end

            %Stop sequence. This allows pulse blaster to run the same
            %sequence again by calling the runSequence function
            stopSequence(obj.pulseBlaster)

            pause(obj.forcedCollectionPauseTime)

            obj.DAQ.takeData = false;

            if strcmpi(obj.DAQ.continuousCollection,'off')
               dataOut = dataOut./n;
               break
            end

            nPointsTaken = obj.DAQ.dataPointsTaken;

            %If at least 5 data points to compare to
            if sum(obj.data.iteration,"all") > 5
               temp = obj.data.nPoints(obj.data.nPoints ~= 0);
               validPoints = ~isoutlier(temp);
               expectedDataPoints = mean(temp(validPoints), "all");
               if nPointsTaken > expectedDataPoints*(1+obj.nPointsTolerance) ||...
                     nPointsTaken < expectedDataPoints*(1-obj.nPointsTolerance)
                  successfulCollection = false;
               else
                  successfulCollection = true;
               end
            else
               expectedDataPoints = obj.pulseBlaster.sequenceDurations.sent.dataNanoseconds;
               expectedDataPoints = (expectedDataPoints/1e9) * obj.DAQ.sampleRate;
               if nPointsTaken > expectedDataPoints*1.05 || nPointsTaken < expectedDataPoints*.95
                  successfulCollection = false;
               else
                  successfulCollection = true;
               end
            end

            if successfulCollection
               if ~all(cell2mat(obj.odometer) == 0)
                  obj.data.failedPoints(obj.odometer{:},obj.data.iteration(obj.odometer{:})+1) = nPauseIncreases;
               end
               if nPauseIncreases ~= 0
                  obj.forcedCollectionPauseTime = originalPauseTime;
                  for ii = 1:numel(bufferPulses)
                     obj.pulseBlaster = modifyPulse(obj.pulseBlaster,bufferPulses(ii),'duration',bufferDuration,false);
                  end
                  obj.pulseBlaster = sendToInstrument(obj.pulseBlaster);
               end
               break

            elseif nPauseIncreases < obj.maxFailedCollections
               nPauseIncreases = nPauseIncreases + 1;
               if obj.notifications
                  warning('Obtained %.4f percent of expected data points\nIncreasing forced pause time temporarily (%d times)',...
                     (100*nPointsTaken)/expectedDataPoints,nPauseIncreases)
               end
               obj.forcedCollectionPauseTime = obj.forcedCollectionPauseTime + originalPauseTime;
               %Increases intermission buffer duration by 2 * number
               %of failed collections
               for ii = 1:numel(bufferPulses)
                  obj.pulseBlaster = modifyPulse(obj.pulseBlaster,bufferPulses(ii),'duration',bufferDuration+(2*nPauseIncreases),false);
               end
               obj.pulseBlaster = sendToInstrument(obj.pulseBlaster);
               pause(.1)%For next data point to come in before discarding the read
               %Discards any data that might have "carried
               %over" from the previous data point
               if obj.DAQ.handshake.NumScansAvailable > 10
                  [~] = read(obj.DAQ.handshake,obj.DAQ.handshake.NumScansAvailable,"OutputFormat","Matrix");
               end
            else
               obj.forcedCollectionPauseTime = originalPauseTime;
               stop(obj.DAQ.handshake)
               error('Failed %d times to obtain correct number of data points. Latest percentage: %.4f',...
                  nPauseIncreases,(100*nPointsTaken)/expectedDataPoints)
            end
         end

         if strcmpi(obj.DAQ.continuousCollection,'on')
            [obj,dataOut] = finishContinuousCollectionProcessing(obj,dataOut);
         end
      end

      function [obj,dataOut] = finishContinuousCollectionProcessing(obj,dataOut)
         dataOut(1) = obj.DAQ.handshake.UserData.reference;
            dataOut(2) = obj.DAQ.handshake.UserData.signal;
            %FIX THIS**** Should be dividing by signal data points or
            %reference data points, not total/2
            if strcmp(obj.DAQ.dataAcquirementMethod,'Voltage')
               if strcmpi(obj.DAQ.differentiateSignal,'on')
                  dataOut(1:2) = dataOut(1:2) ./ (obj.DAQ.dataPointsTaken/2);
               else
                  dataOut(1:2) = dataOut(1:2) ./ (obj.DAQ.dataPointsTaken);
               end
            end
            if obj.DAQ.handshake.UserData.currentCounts > 3e9
               printOut(obj.DAQ,'Counts nearing max value. Resetting counter')
               stop(obj.DAQ.handshake)
               resetcounters(obj.DAQ.handshake)
               start(obj.DAQ.handshake)
            end       
      end

      function [obj,dataOut,nPointsTaken] = getSCMOSData(obj)
         %Takes image and outputs as data

         %Output of takeImage is a cell array for meanImages where each cell is the average image for each set of
         %bounds while frameStacks if a cell array where each cell is a 3D array where each 2D slice is one frame
         %from the camera and each cell corresponds to a different set of bounds

         %Takes image using the camera and the current settings
         [meanImages,frameStacks] = takeImage(obj.hamm);

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
         nPointsTaken = obj.hamm.framesPerTrigger;
      end

      function obj = plotData(obj,dataIn,plotName,varargin)
         %4th argument is y axis label if desired
         %5th argument is selecting which set of bounds to use if multiple are present (defaults to first)
         %6th argument is boolean to flip scan axes (1st scan made y, 2nd made x)
         %7th argument is update location. Defaults to current odometer location
         %8th argument is x offset
         %9th argument is overriding x bounds
         %Expects matrix of numbers, no cell or strings etc.
         %Does not work for 2D scans using manual steps

         %Prevents errors in variable name by swapping space with
         %underscore
         plotTitle = plotName;
         plotName(plotName==' ') = '_';

         %Creates a figure if one does not already exist
         if ~isfield(obj.plots,plotName) ||  ~isfield(obj.plots.(plotName),'figure') || ~ishandle(obj.plots.(plotName).figure)
            obj.plots.(plotName).figure = figure('Name',plotTitle,'NumberTitle','off');
         end

         %Creates axes if one does not already exist
         if ~isfield(obj.plots.(plotName),'axes') || ~isvalid(obj.plots.(plotName).axes)
            obj.plots.(plotName).axes = axes(obj.plots.(plotName).figure);
         end

         %If there is already some kind of data displayed (line or image)
         if ~isfield(obj.plots.(plotName),'dataDisplay') || ~isvalid(obj.plots.(plotName).dataDisplay)
            replot = true;
         else
            replot = false;
         end

         %Check for 1D vs 2D
         %Find where CData is different and replace

         if isscalar(obj.scan) %1D data

            %If multiple sets of bounds, choose first or based on 5th argument
            if isa(obj.scan.bounds,'cell') && ~obj.useManualSteps
               if nargin >= 5 && ~isempty(varargin{2}) && isscalar(varargin{2})
                  xBounds = obj.scan.bounds{varargin{2}};
                  stepSize = obj.scan.stepSize(varargin{2});
               else
                  xBounds = obj.scan.bounds{1};
                  stepSize = obj.scan.stepSize{1};
               end
            elseif ~obj.useManualSteps
               xBounds = obj.scan.bounds;
               stepSize = obj.scan.stepSize;
            end

            %Adds x offset to bounds if given as argument
            if nargin >= 8 && ~isempty(varargin{5})
               xBounds = xBounds + varargin{5};
            end       

            if nargin >= 9 && ~isempty(varargin{6})
               xBounds = varargin{6};
               stepSize = abs((xBounds(2)-xBounds(1))/(obj.scan.nSteps-1));
            end
            
            %x axis isn't the same. Assumed to be different plot entirely
               if (~isfield(obj.plots,plotName) || ~isfield(obj.plots.(plotName),'axes') || ~isfield(obj.plots.(plotName),'dataDisplay'))||...
                       (~isvalid(obj.plots.(plotName).axes) || ~isvalid(obj.plots.(plotName).dataDisplay)) ||...
                       (~obj.useManualSteps && any(obj.plots.(plotName).axes.XLim ~= xBounds) ||...
                       (~obj.useManualSteps && numel(obj.plots.(plotName).dataDisplay.YData) ~= obj.scan.nSteps))  || ...
                     (obj.useManualSteps && obj.plots.(plotName).dataDisplay.XData ~= obj.manualSteps)
                  replot = true;
               end

               if replot
                  %Creates x axis from manual steps or from scan settings
                  if obj.useManualSteps
                     xAxis = obj.manualSteps;
                  else
                     xAxis = xBounds(1):stepSize:xBounds(2);
                  end

                  emptyData = zeros(1,obj.scan.nSteps);

                  %Creates the actual plot as a line
                  obj.plots.(plotName).dataDisplay = plot(obj.plots.(plotName).axes,xAxis,emptyData);

                  %Add x and, optionally, y labels
                  xlabel(obj.plots.(plotName).axes,obj.scan.parameter)
                  if nargin >= 4 && ~isempty(varargin{1})
                     ylabel(obj.plots.(plotName).axes,varargin{1})
                  end
                  title(obj.plots.(plotName).axes,[plotTitle,', ',obj.scan.notes])           
               
                  obj.plots.(plotName).axes.XLim = xBounds;

                  obj.plots.(plotName).completedPoints = boolean(zeros(1,obj.scan.nSteps));
               end               

               %Change current data point value
               obj.plots.(plotName).dataDisplay.YData(obj.odometer{1}) = dataIn;   

               %Set current data point to being completed
               obj.plots.(plotName).completedPoints(obj.odometer{1}) = true;

               %Replace value of all incomplete data points
               completePoints = obj.plots.(plotName).completedPoints;
               if ~all(completePoints)
                   meanVal = mean(obj.plots.(plotName).dataDisplay.YData(completePoints));
                   stdVal = std(obj.plots.(plotName).dataDisplay.YData(completePoints));
                   obj.plots.(plotName).dataDisplay.YData(~completePoints) = meanVal-(stdVal*3);
               end

               return
         end

         %For 2D data

         if obj.useManualSteps
            error('plotData function does not work for 2D data using manual steps')
         end

         for ii = 1:2
            %Gets bounds and step size for both scans
            if isa(obj.scan(ii).bounds,'cell')
               if nargin >= 5 && ~isempty(varargin{2}) && isscalar(varargin{2})
                  imageBounds{ii} = obj.scan(ii).bounds{varargin{2}}; %#ok<*AGROW>
                  stepSize(ii) = obj.scan(ii).stepSize{varargin{2}};
                  nSteps(ii) = obj.scan(ii).nSteps{varargin{2}};
               else
                  imageBounds{ii} = obj.scan(ii).bounds{1};
                  stepSize(ii) = obj.scan(ii).stepSize{1};
                  nSteps(ii) = obj.scan(ii).nSteps{1};
               end
            else
               imageBounds{ii} = obj.scan(ii).bounds;
               stepSize(ii) = obj.scan(ii).stepSize;
               nSteps(ii) = obj.scan(ii).nSteps;
            end
            params{ii} = obj.scan(ii).parameter;
         end

         %Flip scan order (make scan 2 x and scan 1 y)
         if nargin >= 6 && ~isempty(varargin{3}) && varargin{3}
            imageBounds = flip(imageBounds);
            stepSize = flip(stepSize);
            nSteps = flip(nSteps);
            params = flip(params);
         end         
         
         if ~replot && (any(obj.plots.(plotName).dataDisplay.XData ~= imageBounds{2}) || any(obj.plots.(plotName).dataDisplay.YData ~= imageBounds{1}))
            replot = true;
         end

         if replot
            emptyImage = zeros(nSteps(1),nSteps(2));
            obj.plots.(plotName).dataDisplay = imagesc(obj.plots.(plotName).axes,emptyImage);
            % axis(obj.plots.(plotName).axes,'square')%Makes pixel size square, not stretched out
            % obj.plots.(plotName).axes.Colormap = cmap2gray(obj.plots.(plotName).axes.Colormap);
            obj.plots.(plotName).colorbar = colorbar(obj.plots.(plotName).axes);
            xlabel(obj.plots.(plotName).axes,params{2})
            ylabel(obj.plots.(plotName).axes,params{1})
            title(obj.plots.(plotName).axes,[plotTitle,' - ', obj.scan(1).notes])
            obj.plots.(plotName).dataDisplay.XData = imageBounds{2};
            obj.plots.(plotName).dataDisplay.YData = imageBounds{1};
            obj.plots.(plotName).axes.XLim = imageBounds{2};
            obj.plots.(plotName).axes.YLim = imageBounds{1};
            obj.plots.(plotName).axes.YDir = 'reverse';
            %The following makes the image look nicer, otherwise it cuts the edge points in half
            obj.plots.(plotName).axes.XLim(2) = obj.plots.(plotName).axes.XLim(2) + stepSize(2)/2;
            obj.plots.(plotName).axes.XLim(1) = obj.plots.(plotName).axes.XLim(1) - stepSize(2)/2;
            obj.plots.(plotName).axes.YLim(2) = obj.plots.(plotName).axes.YLim(2) + stepSize(1)/2;
            obj.plots.(plotName).axes.YLim(1) = obj.plots.(plotName).axes.YLim(1) - stepSize(1)/2;           
            
            for ii = 1:numel(obj.scan)
                stepList(ii) = obj.scan(ii).nSteps;
            end
            obj.plots.(plotName).completedPoints = boolean(stepList);
            if isfield(obj.plots.(plotName),'minValue')
                obj.plots.(plotName) = rmfield(obj.plots.(plotName),'minValue');
                obj.plots.(plotName) = rmfield(obj.plots.(plotName),'maxValue');
            end
         end

         %Adds data for current odometer location
         obj.plots.(plotName).dataDisplay.CData(obj.odometer{:}) = dataIn;

         %Set current data point to being completed
         obj.plots.(plotName).completedPoints(obj.odometer{:}) = true;

         if ~isfield(obj.plots.(plotName),'minValue')
             obj.plots.(plotName).minValue = dataIn;
             obj.plots.(plotName).maxValue = dataIn+1;
         else
             if dataIn < obj.plots.(plotName).minValue
                 obj.plots.(plotName).minValue = dataIn;
             end
             if dataIn > obj.plots.(plotName).maxValue
                 obj.plots.(plotName).maxValue = dataIn;
             end
         end

         obj.plots.(plotName).axes.CLim = [obj.plots.(plotName).minValue obj.plots.(plotName).maxValue];
      end

      function obj = plotFullDataSet(obj,plotName,xAxisData,yAxisData,varargin)
         %5th argument is cell array for labels and title ('x','y','title' in first column, 2nd column is string)
         %6th argument is cell array of vertical bar name + location

         %inputs should be just xdata and ydata
         %Difference from plotData only in updating every value each time

         %Prevents errors in variable name by swapping space with underscore
         plotTitle = plotName;
         plotName(plotName==' ') = '_';

         %Creates a figure if one does not already exist
         if ~isfield(obj.plots,plotName) ||  ~isfield(obj.plots.(plotName),'figure') || ~ishandle(obj.plots.(plotName).figure)
            obj.plots.(plotName).figure = figure('Name',plotTitle,'NumberTitle','off');
         end

         %Creates axes if one does not already exist
         if ~isfield(obj.plots.(plotName),'axes') || ~isvalid(obj.plots.(plotName).axes)
            obj.plots.(plotName).axes = axes(obj.plots.(plotName).figure);
         end

         %Check if data display (line) is valid, replot if not
         if ~isfield(obj.plots.(plotName),'dataDisplay') || ~isvalid(obj.plots.(plotName).dataDisplay)
            %Creates the actual plot as a line
            obj.plots.(plotName).dataDisplay = plot(obj.plots.(plotName).axes,xAxisData,yAxisData);

            if nargin >= 5 && ~isempty(varargin{1})
               plotInfoCell = varargin{1};
               if size(plotInfoCell,2) ~= 2 || ~isa(plotInfoCell,'cell')
                  error('plot info cell (5th input) must be cell array with 2 columns')
               end
               %Add x label, y label, and title if given in cell array
               xLabelLocation = cellfun(@(a)strcmpi(a,'x')||strcmpi(a,'x label'),plotInfoCell(:,1));
               yLabelLocation = cellfun(@(a)strcmpi(a,'y')||strcmpi(a,'y label'),plotInfoCell(:,1));
               titleLocation = cellfun(@(a)strcmpi(a,'title'),plotInfoCell(:,1));
               if sum(xLabelLocation) == 1
                  xlabel(obj.plots.(plotName).axes,plotInfoCell{xLabelLocation,2})
               end
               if sum(yLabelLocation) == 1
                  ylabel(obj.plots.(plotName).axes,plotInfoCell{yLabelLocation,2})
               end
               if sum(titleLocation) == 1
                  title(obj.plots.(plotName).axes,plotInfoCell{titleLocation,2})
               end
            end

            %Creates x (vertical) lines at locations specified in 1st column of 6th argument with labels from 2nd column
            %of 6th argument
            if nargin >= 6 && ~isempty(varargin{2})
               xLinesCell = varargin{2};
               if size(xLinesCell,2) ~= 2 || ~isa(xLinesCell,'cell')
                  error('x lines cell (6th input) must be cell array with 2 columns')
               end
               for ii = 1:size(xLinesCell,1)
                  obj.plots.(plotName).xLines{ii} = xline(obj.plots.(plotName).axes,xLinesCell{ii,1},'--',xLinesCell{ii,2});
               end
            end
         else
            %Not replotting, just updata data
            obj.plots.(plotName).dataDisplay.XData = xAxisData;
            obj.plots.(plotName).dataDisplay.YData = yAxisData;
         end
      end

      function obj = saveData(obj,saveName)
         %Saves data to file as well as relevant info
         %UNIMPLEMENTED: save images to tif files

         %Check if any data exists
         if isempty(obj.data)
            error('No data to save')
         end

         %Empty struct that will contain relevant information
         dataInfo = {};
         n = 0;

         %Adds RF info
         if ~isempty(obj.SRS_RF)
            n = n+1;
            dataInfo{n,1} = 'RF frequency';
            dataInfo{n,2} = obj.SRS_RF.frequency;
            n = n+1;
            dataInfo{n,1} = 'RF amplitude';
            dataInfo{n,2} = obj.SRS_RF.amplitude;
         end

         %Adds pulse sequence
         if ~isempty(obj.pulseBlaster)
            n = n+1;
            dataInfo{n,1} = 'Pulse sequence';
            dataInfo{n,2} = obj.pulseBlaster.sequenceSentToPulseBlaster;
            n = n+1;
            dataInfo{n,1} = 'Number of loops for pulse sequence';
            dataInfo{n,2} = obj.pulseBlaster.nTotalLoops;
         end

         %Adds camera info
         if ~isempty(obj.hamm)
            n = n+1;
            dataInfo{n,1} = 'Frames per trigger';
            dataInfo{n,2} = obj.hamm.framesPerTrigger;
            n = n+1;
            dataInfo{n,1} = 'Exposure time';
            dataInfo{n,2} = obj.hamm.exposureTime;
         end

         %Adds scan info
         if ~isempty(obj.scan)
            n = n+1;
            dataInfo{n,1} = 'Scan info';
            dataInfo{n,2} = obj.scan;
         end

         %Saves data along with found info
         dataToSave = obj.data;
         save(saveName,"dataToSave","dataInfo")

      end

      function obj = overlapAlgorithm(obj,algorithmType,params)
         %Runs one of the overlap algorithms to get stage in position for
         %SM experiment

         %Does not alter bounds of image taken

         mustContainField(params,{'nFrames','exposureTime','highPass','gaussianRatio'})

         %Change image settings to take desired image, to revert
         %settings once finished
         oldInfo.framesPerTrigger = obj.hamm.framesPerTrigger;
         obj.hamm.framesPerTrigger = params.nFrames;
         oldInfo.outputFullImage = obj.hamm.outputFullImage;
         obj.hamm.outputFullImage = false;
         oldInfo.outputFrameStack = obj.hamm.outputFrameStack;
         obj.hamm.outputFrameStack = false;
         oldInfo.exposureTime = obj.hamm.exposureTime;
         obj.hamm.exposureTime = params.exposureTime;

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
               obj = relativeMove(obj.PIstage,'x',-params.separationDistance);
               obj = relativeMove(obj.PIstage,'y',-params.separationDistance);

               %Takes image used to determine distance
               im = takeImage(obj.hamm);

               %Gets position estimate using 1D gaussian fits for each axis
               %(see function)
               [xEst,yEst] = experiment.double1DGaussian(im,params.highPass,params.gaussianRatio);

               %Convert to microns
               xEst = xEst/params.micronToPixel;
               yEst = yEst/params.micronToPixel;

               %Move the stage to the estimate for x and y
               obj = relativeMove(obj.PIstage,'x',xEst);
               obj = relativeMove(obj.PIstage,'y',yEst);


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
                     obj.PIstage = relativeMove(obj.PIstage,'x',-r(1));
                     obj.PIstage = relativeMove(obj.PIstage,'y',-r(2));
                  else
                     %Increment step of x and y
                     obj.PIstage = relativeMove(obj.PIstage,'x',stepIncrements(1));
                     obj.PIstage = relativeMove(obj.PIstage,'y',stepIncrements(2));
                  end

                  %Takes image used to estimate location
                  im = takeImage(obj.hamm);

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
                     obj.PIstage = relativeMove(obj.PIstage,'x',estimatedIntercept-params.radius(ii));
                  else
                     obj.PIstage = relativeMove(obj.PIstage,'y',estimatedIntercept-params.radius(ii));
                  end

               end
         end

         %Sets camera settings back to prior status
         obj.hamm.framesPerTrigger = oldInfo.framesPerTrigger;
         obj.hamm.outputFullImage = oldInfo.outputFullImage;
         obj.hamm.outputFrameStack = oldInfo.outputFrameStack;
         obj.hamm.exposureTime = oldInfo.exposureTime;

      end

      function [obj,outlierArray] = findDataOutliers(obj,varargin)
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
               dataset = obj.data.nPoints;
            case 'contrast'
               dataset = cellfun(@(x)(x(1)-x(2))/x(1),obj.data.values,'UniformOutput',false);
            case 'reference'
               dataset = cellfun(@(x)x(1),obj.data.values,'UniformOutput',false);
         end

         if nargin > 3 && ~isempty(varargin{3})
            dataset = varargin{3};
         end

         outlierArray = isoutlier(dataset,"mean","ThresholdFactor",outlierThreshold,ndims(dataset));

      end

      function obj = subtractBaseline(obj,baseline)
         %Subtracts baseline value from all data within current scan value

         obj.data.values{obj.odometer{:},obj.data.iteration(obj.odometer{:})} = obj.data.values{obj.odometer{:},obj.data.iteration(obj.odometer{:})} - baseline;
      end

      function obj = convertToRate(obj,varargin)
         %Divides current value by half the time, in seconds, of the data collection for sequence sent to pulse blaster
         %Half the time because half is for reference, half for signal

         %If custom ratio of data time is given, multiple found data time by that
         dataTime = obj.pulseBlaster.sequenceDurations.sent.dataNanoseconds/2;
         if nargin > 1
            dataTime = dataTime .* varargin{1};
         end

         obj.data.values{obj.odometer{:},obj.data.iteration(obj.odometer{:})} = obj.data.values{obj.odometer{:},obj.data.iteration(obj.odometer{:})}...
            ./ (dataTime * 1e-9);
      end
   
      function [obj,fftOut,frequencyAxis] = dataFourierTransform(obj,iterations,dataType,varargin)
         %Frequency axis in Hz
         %4th argument is boolean for incorporating RF strengh. If so, freq axis is in Hz/T

         % Preallocate array for all data points
         preFFTData = zeros(obj.scan.nSteps, numel(iterations));
         
         % Extract data based on type using vectorized operations
         switch dataType
            case {'ref','r','reference'}
               for ii = 1:numel(iterations)
                  preFFTData(:,ii) = cellfun(@(x) x(1), obj.data.values(:,iterations(ii)));
               end
            case {'sig','s','signal'}
               for ii = 1:numel(iterations)
                  preFFTData(:,ii) = cellfun(@(x) x(2), obj.data.values(:,iterations(ii)));
               end
            case {'con','c','contrast'}
               for ii = 1:numel(iterations)
                  refData = cellfun(@(x) x(1), obj.data.values(:,iterations(ii)));
                  sigData = cellfun(@(x) x(2), obj.data.values(:,iterations(ii)));
                  preFFTData(:,ii) = (refData - sigData) ./ refData;
               end
         end

         % Perform FFT on all iterations at once
         fftOut = abs(fftshift(fft(preFFTData - mean(preFFTData, 1), [], 1)));
         % Single sided FFT
         fftOut = fftOut(ceil((obj.scan.nSteps+1)/2)+1:end, :);
         % Average across iterations
         fftOut = mean(fftOut, 2);

         frequencyStepSize = obj.scan.stepSize(1)*1e-9;%Hz
         frequencyAxis = (1:(obj.scan.nSteps-1)/2)/(frequencyStepSize*obj.scan.nSteps);

         %Boolean for incorporating RF strength
         if nargin >= 4 && ~isempty(varargin{1}) && varargin{1}
            frequencyAxis = frequencyAxis/(magnetStrength(obj.SRS_RF.frequency,'strength')*1e-4);%1e4 is gauss to tesla
         end
      end
   end

   methods
      %Set/Get for instruments

      %General function for get/set of instruments
      function objectMatch = findInstrument(obj,identifierInput)
         %Finds the location within instrumentCells for a given instrument

         if numel(obj.instrumentIdentifiers) ~= numel(obj.instrumentCells)
            %Ensures up to date list of instruments
            obj = getInstrumentNames(obj);
            
         end

         %Obtain proper identifier for the input and compare with instruments present
         properIdentifier = instrumentType.giveProperIdentifier(identifierInput);
         objectMatch = strcmp(obj.instrumentIdentifiers,properIdentifier);

         if sum(objectMatch) > 2
            error('More than 1 instrument with identifier %s present')
         end

      end

      function s = getInstrumentVal(obj,instrumentName)
         instrumentLocation = findInstrument(obj,instrumentName);
         if ~any(instrumentLocation)
            s = [];
         else
            s = obj.instrumentCells{instrumentLocation};
         end
      end

      function obj = setInstrumentVal(obj,instrumentName,val)
         instrumentLocation = findInstrument(obj,instrumentName);
         if sum(instrumentLocation) == 0
            if ~any(strcmp({'RF_generator','stage','pulse_blaster','laser','kinesis_piezo','deformable_mirror','DAQ_controller','cam'},class(val)))
               error('Cannot set %s as it does not exist',instrumentName)
            end
            obj.instrumentCells{end+1} = val;
         else
            obj.instrumentCells{instrumentLocation} = val;
         end
      end

      %Specific instruments. Add/Remove as needed to correspond to
      %dependent variables
      function s = get.pulseBlaster(obj)
         s = getInstrumentVal(obj,'pulse blaster');
      end
      function obj = set.pulseBlaster(obj,val)
         obj = setInstrumentVal(obj,'pulse blaster',val);
      end

      function s = get.PIstage(obj)
         s = getInstrumentVal(obj,'stage');
      end
      function obj = set.PIstage(obj,val)
         obj = setInstrumentVal(obj,'stage',val);
      end

      function s = get.SRS_RF(obj)
         s = getInstrumentVal(obj,'srs');
      end
      function obj = set.SRS_RF(obj,val)
         obj = setInstrumentVal(obj,'srs',val);
      end

      function s = get.windfreak_RF(obj)
         s = getInstrumentVal(obj,'wf');
      end
      function obj = set.windfreak_RF(obj,val)
         obj = setInstrumentVal(obj,'wf',val);
      end

      function s = get.DAQ(obj)
         s = getInstrumentVal(obj,'daq');
      end
      function obj = set.DAQ(obj,val)
         obj = setInstrumentVal(obj,'daq',val);
      end

      function s = get.DDL(obj)
         s = getInstrumentVal(obj,'ddl');
      end
      function obj = set.DDL(obj,val)
         obj = setInstrumentVal(obj,'ddl',val);
      end

      function s = get.hamm(obj)
         s = getInstrumentVal(obj,'hamamatsu');
      end
      function obj = set.hamm(obj,val)
         obj = setInstrumentVal(obj,'hamamatsu',val);
      end

      function s = get.ndYAG(obj)
         s = getInstrumentVal(obj,'ndYAG');
      end
      function obj = set.ndYAG(obj,val)
         obj = setInstrumentVal(obj,'ndYAG',val);
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
               % Fit a Gaussian curve to the data
               try
                   % Create fit object with a single Gaussian
                   gaussFit = fit(positionVector(:), dataVector(:), 'gauss1');
                   coeffs = coeffvalues(gaussFit);
                   
                   % Extract parameters: coeffs = [a1,b1,c1] where
                   % f(x) = a1*exp(-((x-b1)/c1)^2)
                   % b1 is the peak position
                   maxPosition = coeffs(2);
                   maxValue = coeffs(1); % Peak amplitude
                   
                   % Validate the fit result
                   % Check 1: Position should be within the scanned range
                   if maxPosition < min(positionVector) || maxPosition > max(positionVector)
                       warning('Gaussian fit peak position outside scanned range. Using max value method instead.');
                       [maxValue,maxPosition] = experiment.optimizationAlgorithm(dataVector,positionVector,'max value');
                       return;
                   end
                   
                   % Check 2: R-squared value should be reasonable (above 0.7)
                   gof = goodness(gaussFit);
                   if gof.rsquare < 0.7
                       warning('Poor Gaussian fit quality (R² < 0.7). Using max value method instead.');
                       [maxValue,maxPosition] = experiment.optimizationAlgorithm(dataVector,positionVector,'max value');
                       return;
                   end
                   
                   % Check 3: Width should be reasonable (not too narrow or wide)
                   width = abs(coeffs(3));
                   scanRange = max(positionVector) - min(positionVector);
                   if width < scanRange*0.05 || width > scanRange*0.5
                       warning('Gaussian fit width unreasonable. Using max value method instead.');
                       [maxValue,maxPosition] = experiment.optimizationAlgorithm(dataVector,positionVector,'max value');
                       return;
                   end
                   
               catch ME
                   warning(ME.identifier, 'Gaussian fitting failed: %s\nUsing max value method instead.', ME.message);
                   [maxValue,maxPosition] = experiment.optimizationAlgorithm(dataVector,positionVector,'max value');
               end
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
