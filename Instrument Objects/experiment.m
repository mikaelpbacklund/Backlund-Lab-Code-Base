classdef experiment
   %To do:
   %Multi-dimensional scans
      %Scan multiple spatial axes at once like pulse addresses?
   %Data in the form of images
   
   
   properties
      scan %Structure containing info specific to each scan within the broader operation
      odometer %Keeps track of position in scan
      data %Stores data for each data point within a scan including its iteration
      instrumentNames
      plots
      manualSteps
      useManualSteps = false;%Use steps entered by user rather than evenly spaced
      forcedCollectionPauseTime = .1;%To fully compensate for DAQ and pulse blaster and prevent periodic changes in data collected
   end
   
   methods
      
      function [h,instrumentCells] = takeNextDataPoint(h,instrumentCells,acquisitionType)
         %Check if valid configuration (always need PB and DAQ, sometimes
         %needs RF or stage, rarely needs laser)
         
         %If the odometer is at the max value, end this function without
         %incrementing anything
         if all(h.odometer == [h.scan.nSteps])
            return
         end
         
         %Increment odometer to next value
         newOdometer = experiment.incrementOdometer(h.odometer,[h.scan.nSteps]);
         
         %Determine which scans need to be changed. Scans whose odometer
         %value isn't changed don't need to be set again. Often gets 1
         %value corresponding to the most nested scan being incremented
         needChanging = find(newOdometer ~= h.odometer);
         
         for ii = needChanging
            %Sets the instrument's parameter to the value determined by
            %the step of the scan
            [h,instrumentCells] = setInstrument(h,instrumentCells,ii);
         end
         
         %Sets odometer to the incremented value
         h.odometer = newOdometer;
         
         %Actually takes the data using selected acquisition type
         [h,dataOut] = getData(h,instrumentCells,acquisitionType);
         
         %Adds previous iteration to all prior iterations
         h.data.previous{h.odometer} = h.data.previous{h.odometer} + h.data.current{h.odometer};
         
         %Increments number of data points taken by 1
         h.data.iteration(h.odometer) = h.data.iteration(h.odometer) + 1;
         
         %Takes data and puts it in the current iteration spot for this
         %data point
         h.data.current{h.odometer} = dataOut;
      end
      
      function [h,instrumentCells] = setInstrument(h,instrumentCells,scanToChange)
         currentScan = h.scan(scanToChange);%Pulls current scan to change
         
         if ~isa(currentScan.bounds,'cell')%Cell indicates multiple new values
            if h.useManualSteps
               newValue = h.manualSteps{scanToChange};
               if h.odometer(scanToChange) == 0
                   newValue = newValue(1);
               else
                   newValue = newValue(h.odometer(scanToChange));
               end
            else
               newValue = currentScan.bounds(1) + currentScan.stepSize*h.odometer(scanToChange);%Computes new value
            end
         end
         
         %Finds which number the current instrument corresponds to in
         %instrumentCells
         relevantInstrument = instrumentCells{strcmpi(h.instrumentNames,currentScan.instrument)};
         
         %Does heavy lifting of actually sending commands to instrument
         switch class(relevantInstrument)
            
            case 'RF_generator'
               switch lower(currentScan.parameter)
                  case 'frequency'
                     relevantInstrument = setFrequency(relevantInstrument,newValue);
               end
               
            case 'pulse_blaster'
               switch lower(currentScan.parameter)
                  case 'duration'
                     %For each pulse address, modify the duration based on
                     %the new values
                     for ii = 1:numel(currentScan.address)
                        if h.manualSteps
                           %Get the manual steps for the current scan, for
                           %the address dictated by the loop, for the
                           %current step of that scan
                           if h.odometer(scanToChange) == 0
                               newValue = h.manualSteps{scanToChange}{ii}(1);
                           else
                               newValue = h.manualSteps{scanToChange}{ii}(h.odometer(scanToChange));
                           end
                        else
                           newValue = currentScan.bounds{ii}(1) + currentScan.stepSize(ii)*h.odometer(scanToChange);
                        end                        
                        relevantInstrument = modifyPulse(relevantInstrument,currentScan.address(ii),'duration',newValue);
                     end
                     relevantInstrument = sendToInstrument(relevantInstrument);
               end
               
            case 'stage'
                relevantInstrument = absoluteMove(relevantInstrument,currentScan.parameter,newValue);          
         end
         
         %Feeds instrument info back out
         instrumentCells{strcmp(h.instrumentNames,currentScan.instrument)} = relevantInstrument;
         
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
         
         %If you are using a manual scan, much of the scan addition process
         %is different
         if h.useManualSteps
            mustContainField(scanInfo,{'parameter','instrument'})
            if any(cellfun(@isempty,{scanInfo.instrument})) || any(cellfun(@isempty,{scanInfo.parameter}))
               error('All fields must contain non-empty values for each scan')
            end
            scanInfo = mustContainField(scanInfo,'notes',[scanInfo.instrument ' ' scanInfo.parameter]);
            
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
         
         %Scan must have bounds, parameter, and instrument name
         mustContainField(scanInfo,{'bounds','parameter','instrument'})
         
         %Checks for any empty values
         if any(cellfun(@isempty,{scanInfo.bounds})) || any(cellfun(@isempty,{scanInfo.instrument})) || any(cellfun(@isempty,{scanInfo.parameter}))
            error('All fields must contain non-empty values for each scan')
         end
         
         %Scan can optionally have notes field. If it does not, default is
         %derived from instrument and parameter names
         scanInfo = mustContainField(scanInfo,'notes',{[scanInfo.instrument ' ' scanInfo.parameter]});
         
         if ~isfield(scanInfo,'stepSize') && ~isfield(scanInfo,'nSteps')
            error('Scan must contain either stepSize or nSteps field')
         end
         
         %Note: I don't think matlab likes structs with dimensionality.
         %Most operations I wish to perform need strange workarounds
         %like assigning a variable before taking each element or
         %needing a for loop to assign every element in a field
         if any(cellfun(@isempty,{scanInfo.stepSize}))
            error('All fields must contain non-empty values for each scan')
         end
         
         b = [scanInfo.bounds];
         if ~isa(b,'cell'),     b = {b};      end
         
         if isfield(scanInfo,'stepSize')
            s = [scanInfo.stepSize];
            n = cellfun(@(x)x(2)-x(1),b);
            
            if numel(s) == 1
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
      
      function h = validExperimentalConfiguration(h,instrumentCells,acquisitionType)
         %Checks instrument cells and scan settings to see if the necessary
         %connections have been made
         
         h = getInstrumentNames(h,instrumentCells);
         
         switch lower(acquisitionType)
            case 'pulse sequence'
               checkInstrument(h,instrumentCells,'pulse_blaster',acquisitionType)
               checkInstrument(h,instrumentCells,'DAQ_controller',acquisitionType)
            case 'scmos'
            otherwise
               error('acquisitionType must be ''pulse sequence'' or ''sCMOS''')
         end
         
         %If there isn't a scan, nothing else required to check
         if isempty(h.scan)
            return
         end
         
         for ii = {h.scan.instrument}
            checkInstrument(h,instrumentCells,ii{1})
         end
      end

      function dataAverage = findDataAverage(h,varargin)
         if nargin == 2
            dataPoint = varargin{1};
            dataAverage = h.data.current{dataPoint} + h.data.previous{dataPoint};
         else
            dataAverage = cell2mat(h.data.current) + cell2mat(h.data.previous);
         end
         
         dataAverage = dataAverage ./ h.data.iteration;
         dataAverage(isnan(dataAverage)) = 0;
      end
      
      function [h,instrumentCells] = resetScan(h,instrumentCells)
         %Sets the scan to the starting value for each dimension of the
         %scan
         h.odometer = ones(1,numel(h.scan));
         for ii = 1:numel(h.odometer)
            [h,instrumentCells] = setInstrument(h,instrumentCells,ii);
         end
         h.odometer(end) = 0;
      end
      
      function h = resetAllData(h,resetValue)
         %Resets all stored data within the experiment object

         %Squeeze is necessary to remove first dimension if there is a
         %multi-dimensional scan
         h.data.iteration = squeeze(zeros(1,h.scan.nSteps(1)));
    
         %Makes cell array of equivalent size to above
         h.data.current = num2cell(h.data.iteration);
         
         %This sets every cell to be the value resetValue in the way one
         %might expect the following to do so:
         %h.data.current{:} = resetValue;
         %The above doesn't work due to internal matlab shenanigans but
         %using the deal function is quite helpful
         [h.data.current{:}] = deal(resetValue);
         
         %Copy to "previous" as format is the same
         h.data.previous = h.data.current;
      end
      
      function h = getInstrumentNames(h,instrumentCells)
         %Gets the names for each instrument corresponding to their cell in
         %the input
         h.instrumentNames = cellfun(@(x)class(x),instrumentCells,'UniformOutput',false);
      end
      
      function [h,instrumentCells] = stageOptimization(h,instrumentCells,algorithmType,acquisitionType,sequence,varargin)
         %sequence.steps: cell array of vectors corresponding to the steps for
         %each axis
         %sequence.axes: axes that should be moved during optimization
         %sequence.consecutive: boolean for running axes consecutively or like
         %a scan
         
         if nargin > 5
            rfStatus = varargin{1};
         end
         
         %Steps must be pre-programmed
         mustContainField(sequence,{'steps','axes','consecutive'})
         
         %Abbreviation
         stageObject = instrumentCells{strcmpi('stage',h.instrumentNames)};
         
         %steps input should look like:
         %[-2,-1.5,-1,-.5,0,.5,1,1.5,2]
         %Find current position then add steps to that to get the actual
         %values
         axisNumbers = zeros(1,numel(sequence.axes));
         for ii = 1:numel(sequence.steps)
            %Gets the number corresponding to the axis
            axisNumbers(ii) = find(strcmpi(sequence.axes{ii},stageObject.axisSum(:,1)));
            if isempty(axisNumbers(ii))
               error('%d axis in optimization sequence doesn''t correspond to any axis in the stage object',axisNumbers(ii))
            end
            %Makes steps into absolute locations instead of relative for ease
            %of input later
            sequence.steps{ii} = sequence.steps{ii} + stageObject.axisSum{axisNumbers(ii),2};
         end
         
         switch lower(acquisitionType)
            case 'pulse sequence'
               pb = instrumentCells{strcmpi('pulse_blaster',h.instrumentNames)};
               
               %Stores old information about pulse sequence for retrieval
               %after optimization
               oldSequence = pb.userSequence;
               oldUseTotalLoop = pb.useTotalLoop;
               pb.userSequence = [];
               pb.useTotalLoop = false;
               
               if ~exist('rfStatus','var')
                   assignin('base','rfStatus',rfStatus)
                  error('RF status (6th argument) must be ''on'' ''off'' or ''contrast''')
               end
               switch rfStatus
                  case {'off','on'}
                     channels{1} = {'laser'};
                     channels{2} = {'laser','data'};
                     if strcmpi(rfStatus,'on')
                        channels{1}{end+1} = 'rf';
                        channels{2}{end+1} = 'rf';
                     end
                     
                     clear pulseInfo
                     pulseInfo.activeChannels = channels{1};
                     pulseInfo.duration = 500;
                     pulseInfo.notes = 'Initial buffer';
                     pb = addPulse(pb,pulseInfo);
                     
                     clear pulseInfo
                     pulseInfo.activeChannels = channels{2};
                     pulseInfo.duration = 1e7; %10 milliseconds
                     pulseInfo.notes = 'Taking data';
                     pb = addPulse(pb,pulseInfo);
                     
                     pb = sendToInstrument(pb);
                     
                  case 'contrast'
                   otherwise
                       assignin('base','rfStatus',rfStatus)
                     error('RF status (6th argument) must be ''on'' ''off'' or ''contrast''')
               end
               
               instrumentCells{strcmpi('pulse_blaster',h.instrumentNames)} = pb;
            case 'scmos'
               
         end
         
         
         if sequence.consecutive
            %Default way, runs each axis consecutively
            
            for ii = 1:numel(sequence.axes)
               spatialAxis = sequence.axes{ii};
               dataVector = zeros(1,numel(sequence.steps{ii}));
               for jj = 1:numel(sequence.steps{ii})
                  %Moves to location for taking this data
                  stageObject = absoluteMove(stageObject,spatialAxis,sequence.steps{ii}(jj));
                  
                  %Get data at this location
                  [h,dataOut] = getData(h,instrumentCells,acquisitionType);
                  switch rfStatus
                      case {'off','on'}
                          dataVector(jj) = dataOut(1);
                      case 'contrast'
                          dataVector(jj) = (dataOut(1) - dataOut(2))/dataOut(1);
                  end                  
               end

               assignin('base',"dataVector",dataVector)
               
               [~,maxPosition] = experiment.optimizationAlgorithm(dataVector,sequence.steps{ii},algorithmType);
               stageObject = absoluteMove(stageObject,spatialAxis,maxPosition);

               assignin('base',"maxPosition",maxPosition)
               assignin('base',"stepLocations",sequence.steps{ii})
            end
            
         else
            
         end
         
         %Stores stage object back in instrument cells
         instrumentCells{strcmpi('stage',h.instrumentNames)} = stageObject;
         
         %Set pulse blaster back to previous sequence
         if strcmpi(acquisitionType,'pulse sequence')
            pbLocation = strcmpi('pulse_blaster',h.instrumentNames);
            instrumentCells{pbLocation}.useTotalLoop = oldUseTotalLoop;
            instrumentCells{pbLocation}.userSequence = oldSequence;
            instrumentCells{pbLocation} = sendToInstrument(instrumentCells{pbLocation});
         end
         
      end 
      
      function [h,dataOut] = getData(h,instrumentCells,acquisitionType)
         switch lower(acquisitionType)
            case 'pulse sequence'
               %Find which cells are the DAQ and pulse blaster
               daqNumber = strcmp(h.instrumentNames,'DAQ_controller');
               pulseBlasterNumber = strcmp(h.instrumentNames,'pulse_blaster');
               
               %Reset DAQ in preparation for measurement
               instrumentCells{daqNumber} = resetDAQ(instrumentCells{daqNumber});

               %Start sequence
               runSequence(instrumentCells{pulseBlasterNumber})
               
               %Wait until pulse blaster says it is done running
               while pbRunning(instrumentCells{pulseBlasterNumber})
                  pause(.001)
               end
               
               %Stop sequence. This allows pulse blaster to run the same
               %sequence again by calling the runSequence function
               stopSequence(instrumentCells{pulseBlasterNumber})

               pause(h.forcedCollectionPauseTime)           

               if strcmp(instrumentCells{daqNumber}.differentiateSignal,'on')
                   dataOut(1) = instrumentCells{daqNumber}.handshake.UserData.reference;
                   dataOut(2) = instrumentCells{daqNumber}.handshake.UserData.signal;
               else
                   %Takes data and puts it in the current iteration spot for this
                   %data point
                   dataOut = readData(instrumentCells{daqNumber});
               end

            case 'scmos'
         end
      end
      
      function h = make1DPlot(h,yData,plotName)
         %Creates/Updates plots of a 1D scan
         
         if numel(h.scan) ~= 1
            error('To plot 1D scans, there must only be 1 scan dimension')
         end
         
         %This does not work for images
         mustBeVector(yData)

         if isa(h.scan.bounds,'cell')
             b = h.scan.bounds{1};
             s = h.scan.stepSize(1);
             n = h.scan.nSteps(1);
         else
             b = h.scan.bounds;
             s = h.scan.stepSize;
             n = h.scan.nSteps;
         end

         hasPlotName = isfield(h.plots,plotName);
         if hasPlotName
            hasFig = isfield(h.plots.(plotName),'figure') && ishandle(h.plots.(plotName).figure);
            hasAxes = isfield(h.plots.(plotName),'axes') && ishandle(h.plots.(plotName).axes);
            if hasAxes
                matchingBounds = all(h.plots.(plotName).axes.XLim == b);                
            end
            hasLine = isfield(h.plots.(plotName),'line') && ishandle(h.plots.(plotName).line);
            if hasLine
                matchingSteps = numel(h.plots.(plotName).line.XData) == n;
            end
         else
             hasFig = false;
             hasAxes = false;
             hasLine = false;
         end

         if ~hasPlotName || ~hasFig || ~hasAxes || ~matchingBounds || ~hasLine || ~matchingSteps
             if hasLine
                 delete(h.plots.(plotName).line);
                 h.plots.(plotName) = rmfield(h.plots.(plotName),'line');
             end
             if hasAxes
                 delete(h.plots.(plotName).axes);
                 h.plots.(plotName) = rmfield(h.plots.(plotName),'axes');
             end
             if hasFig
                 delete(h.plots.(plotName).figure);
                 h.plots.(plotName) = rmfield(h.plots.(plotName),'figure');
             end
             %Create new plot
             h.plots.(plotName).figure = figure('Name',plotName,'NumberTitle','off');
             h.plots.(plotName).axes = axes(h.plots.(plotName).figure);             
             xAxis = b(1):s:b(2);
             

             h.plots.(plotName).line = plot(h.plots.(plotName).axes,xAxis,yData);
             h.plots.(plotName).axes.XLim = b;
             title(h.plots.(plotName).axes,strcat(h.scan.notes,' (',plotName,')'))
         else
             %Figure, axes, and line all exist already. Most cases of updating
             %a plot will simply do this
             h.plots.(plotName).line.YData = yData;
         end
         
      end
      
      function c = findContrast(h,varargin)
         if nargin >= 2
            iterationType = varargin{1};
         else
            iterationType = 'average';
         end
         
         switch iterationType
            case {'new','current','recent'}               
               chosenData = h.data.current;
            case {'previous','prior','old'}
               %Dividing by number of iterations is irrelevant for
               %determining contrast as it is relative
               chosenData = h.data.previous;
            case {'average','total',''}
               %See above comment
               chosenData = cellfun(@(x,y)x+y,h.data.current,h.data.previous,'UniformOutput',false);
         end
         
         %Contrast function is optional third input but defaults to
         %(ref-sig)/ref if no function is given
         if nargin >= 3
            contrastFunction = varargin{2};
         else
            contrastFunction = @(x)(x(1)-x(2))/x(1);
         end
         c = cellfun(contrastFunction,chosenData);
         c(isnan(c)) = 0;
      end
      
      function checkInstrument(h,instrumentCells,instrumentName,varargin)
         %Checks if designated object is present and, if it is, whether it
         %is connected
         if nargin == 4
            acquisitionType = varargin{1};
            if ~ismember(instrumentName,h.instrumentNames)
               error('%s object required to perform ''%s'' data acquisition',instrumentName,acquisitionType)
            end
            if ~instrumentCells{strcmp(h.instrumentNames,instrumentName)}.connected
               error('%s must be connected to perform ''%s'' data acquisition',instrumentName,acquisitionType)
            end
         else
            if ~ismember(instrumentName,h.instrumentNames)
               error('%s object required to perform scan on %s',instrumentName,instrumentName)
            end
            if ~instrumentCells{strcmp(h.instrumentNames,instrumentName)}.connected
               error('%s must be connected to perform scan on %s',instrumentName,instrumentName)
            end
         end
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
         
      end
      
   end
end