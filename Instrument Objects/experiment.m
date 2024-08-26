classdef experiment
   %To do:
   %Multi-dimensional scans
   %Scan multiple spatial axes at once like pulse addresses?

   properties
      scan %Structure containing info specific to each scan within the broader operation
      odometer %Keeps track of position in scan
      plots
      manualSteps
      useManualSteps = false;%Use steps entered by user rather than evenly spaced
      forcedCollectionPauseTime = .1;%To fully compensate for DAQ and pulse blaster and prevent periodic changes in data collected
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
      data %Stores data for each data point within a scan including its iteration
      instrumentCells
   end

   methods

      function h= takeNextDataPoint(h,acquisitionType)
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
            h = setInstrument(h,ii);
         end

         %Sets odometer to the incremented value
         h.odometer = newOdometer;

         %Actually takes the data using selected acquisition type
         [h,dataOut,nPoints] = getData(h,acquisitionType);

         %Adds previous iteration to all prior iterations for all cells in
         %this data point
         h.data.previous{h.odometer} = cellfun(@(x,y)x+y,h.data.previous{h.odometer},h.data.current{h.odometer},'UniformOutput',false);

         %Increments number of data points taken by 1
         h.data.iteration(h.odometer) = h.data.iteration(h.odometer) + 1;

         %Takes data and puts it in the current iteration spot for this
         %data point
         h.data.current{h.odometer} = dataOut;
         h.data.nPoints(h.odometer,h.data.iteration(h.odometer)) = nPoints;
      end

      function h = setInstrument(h,scanToChange)
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
               newValue = currentScan.bounds(1) + currentScan.stepSize*(h.odometer(scanToChange)-1);%Computes new value
            end
         end 

         if strcmp(currentScan.identifier,'forcedCollectionPauseTime')
             h.forcedCollectionPauseTime = newValue;
%              if mod(h.odometer,2) == 1
%                  h.SRS_RF.amplitude = 10;
%              else
%                  h.SRS_RF.amplitude = 9;
%              end
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
                     pause(.1)
                   case 'amplitude'
                      relevantInstrument.amplitude = newValue;
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
                           newValue = currentScan.bounds{ii}(1) + currentScan.stepSize(ii)*(h.odometer(scanToChange)-1);
                        end
                        relevantInstrument = modifyPulse(relevantInstrument,currentScan.address(ii),'duration',newValue);
                     end
                     relevantInstrument = sendToInstrument(relevantInstrument);
               end

            case 'stage'
               relevantInstrument = absoluteMove(relevantInstrument,currentScan.parameter,newValue);
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

         %If you are using a manual scan, much of the scan addition process
         %is different
         if h.useManualSteps
            mustContainField(scanInfo,{'bounds','parameter'})
            if any(cellfun(@isempty,{scanInfo.identifier})) || any(cellfun(@isempty,{scanInfo.parameter}))
               error('All fields must contain non-empty values for each scan')
            end
            scanInfo = mustContainField(scanInfo,'notes',[scanInfo.identifier ' ' scanInfo.parameter]);

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
         mustContainField(scanInfo,{'bounds','parameter'})

         %Checks for any empty values
         if any(cellfun(@isempty,{scanInfo.bounds})) || any(cellfun(@isempty,{scanInfo.identifier})) || any(cellfun(@isempty,{scanInfo.parameter}))
            error('All fields must contain non-empty values for each scan')
         end

         %Scan can optionally have notes field. If it does not, default is
         %derived from instrument and parameter names
         scanInfo = mustContainField(scanInfo,'notes',{[scanInfo.identifier ' ' scanInfo.parameter]});

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

      function h = validateExperimentalConfiguration(h,acquisitionType)
         %Checks instrument cells and scan settings to see if the necessary
         %connections have been made

         return %**********very temporary

         h = getInstrumentNames(h);

         switch lower(acquisitionType)
            case 'pulse sequence'
               checkInstrument(h,'pulse_blaster',acquisitionType)
               checkInstrument(h,'DAQ_controller',acquisitionType)
            case 'scmos'
            otherwise
               error('acquisitionType must be ''pulse sequence'' or ''sCMOS''')
         end

         %If there isn't a scan, nothing else required to check
         if isempty(h.scan)
            return
         end

         for ii = {h.scan.identifier}
            checkInstrument(h,ii{1})
         end
      end

      function dataAverage = findDataAverage(h,varargin)
         %Finds average of current and previous iterations for given cell in
         %given data point. 2nd argument is data point (default to odometer
         %reading)
         %Does not support multiple data points

         %2nd argument is cell corresponding to the specific data point
         %within the scan
         if nargin > 1 && ~isempty(varargin{1})
            dataPoint = varargin{1};
         else
            dataPoint = h.odometer;
         end

         %If there have been no iterations, you would get a divide by 0
         %error, instead this function returns 0s matching the dimensions
         %of each cell
         if h.data.iteration(dataPoint) == 0
            dataAverage = cellfun(@(x)zeros(size(x)),h.data.current{dataPoint});
         else
            %Creates cell array with averaged values based on the recorded
            %iteration and current/previous data
            dataAverage = cellfun(@(x,y)x+y,h.data.current{dataPoint},h.data.previous{dataPoint},'UniformOutput',false);
            dataAverage = cellfun(@(x)x./h.data.iteration(dataPoint),dataAverage,'UniformOutput',false);
         end
      end

      function h = resetScan(h)
         %Sets the scan to the starting value for each dimension of the
         %scan
         h = getInstrumentNames(h);
         h.odometer = ones(1,numel(h.scan));
         for ii = 1:numel(h.odometer)
            h = setInstrument(h,ii);
         end
         h.odometer(end) = 0;         
      end

      function h = resetAllData(h,resetValue)
         %Resets all stored data within the experiment object

         %If the reset value isn't a cell, make it a 1x1 cell
         if ~isa(resetValue,'cell')
            a{1} = resetValue;
            resetValue = a;
         end

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

         h.data.nPoints = h.data.iteration';
         h.data.failedPoints = h.data.iteration';
      end

      function h = getInstrumentNames(h)
         %For each instrument get the "proper" identifier
         if isempty(h.instrumentCells)
            h.instrumentIdentifiers = [];
         else
            h.instrumentIdentifiers = cellfun(@(x)instrumentType.giveProperIdentifier(x.identifier),h.instrumentCells,'UniformOutput',false);
         end 
      end

      function h = stageOptimization(h,algorithmType,acquisitionType,sequence,varargin)
         %sequence.steps: cell array of vectors corresponding to the steps for
         %each axis
         %sequence.axes: axes that should be moved during optimization
         %sequence.consecutive: boolean for running axes consecutively or like
         %a scan

         %*****Make sequence, RF status, and data cell all part of settings
         %input to cut down on number of inptus

         if nargin > 4
            rfStatus = varargin{1};
         end

         %Steps must be pre-programmed
         mustContainField(sequence,{'steps','axes','consecutive'})

         %steps input should look like:
         %[-2,-1.5,-1,-.5,0,.5,1,1.5,2]
         %Find current position then add steps to that to get the actual
         %values
         axisNumbers = zeros(1,numel(sequence.axes));
         for ii = 1:numel(sequence.steps)
            %Gets the number corresponding to the axis
            axisNumbers(ii) = find(strcmpi(sequence.axes{ii},h.PIstage.axisSum(:,1)));
            if isempty(axisNumbers(ii))
               error('%d axis in optimization sequence doesn''t correspond to any axis in the stage object',axisNumbers(ii))
            end
            %Makes steps into absolute locations instead of relative for ease
            %of input later
            sequence.steps{ii} = sequence.steps{ii} + h.PIstage.axisSum{axisNumbers(ii),2};
         end

         switch lower(acquisitionType)
            case 'pulse sequence'
               %Stores old information about pulse sequence for retrieval
               %after optimization
               oldSequence = h.pulseBlaster.userSequence;
               oldUseTotalLoop = h.pulseBlaster.useTotalLoop;
               h.pulseBlaster.userSequence = [];
               h.pulseBlaster.useTotalLoop = false;

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
                     h.pulseBlaster = addPulse(h.pulseBlaster,pulseInfo);

                     clear pulseInfo
                     pulseInfo.activeChannels = channels{2};
                     pulseInfo.duration = 1e7; %10 milliseconds
                     pulseInfo.notes = 'Taking data';
                     h.pulseBlaster = addPulse(h.pulseBlaster,pulseInfo);

                     h.pulseBlaster = sendToInstrument(h.pulseBlaster);

                  case 'contrast'
                  otherwise
                     assignin('base','rfStatus',rfStatus)
                     error('RF status (6th argument) must be ''on'' ''off'' or ''contrast''')
               end
            case 'scmos'

         end


         if sequence.consecutive
            %Default way, runs each axis consecutively

            for ii = 1:numel(sequence.axes)
               spatialAxis = sequence.axes{ii};
               dataVector = zeros(1,numel(sequence.steps{ii}));
               for jj = 1:numel(sequence.steps{ii})
                  %Moves to location for taking this data
                  h.PIstage = absoluteMove(h.PIstage,spatialAxis,sequence.steps{ii}(jj));

                  %Get data at this location
                  [h,dataOut] = getData(h,acquisitionType);
                  switch rfStatus
                     case {'off','on'}
                        dataVector(jj) = dataOut(1);
                     case 'contrast'
                        dataVector(jj) = (dataOut(1) - dataOut(2))/dataOut(1);
                  end
               end

               assignin('base',"dataVector",dataVector)

               [~,maxPosition] = experiment.optimizationAlgorithm(dataVector,sequence.steps{ii},algorithmType);
               h.PIstage = absoluteMove(h.PIstage,spatialAxis,maxPosition);

               assignin('base',"maxPosition",maxPosition)
               assignin('base',"stepLocations",sequence.steps{ii})
            end

         else

         end

         %Set pulse blaster back to previous sequence
         if strcmpi(acquisitionType,'pulse sequence')
            h.pulseBlaster.useTotalLoop = oldUseTotalLoop;
            h.pulseBlaster.userSequence = oldSequence;
            h.pulseBlaster = sendToInstrument(h.pulseBlaster);
         end

      end

      function [h,dataOut,nPointsTaken] = getData(h,acquisitionType)
          nPointsTaken = 0;%default to 0
         switch lower(acquisitionType)
            case 'pulse sequence'

                nFailedCollections = 0;

                while true
                    %Reset DAQ in preparation for measurement
                    h.DAQ = resetDAQ(h.DAQ);
                    h.DAQ.takeData = true;

%                     pause(1)

                    %Start sequence
                    runSequence(h.pulseBlaster)

                    %Wait until pulse blaster says it is done running
                    while pbRunning(h.pulseBlaster)
                        pause(.001)
                    end

                    %Stop sequence. This allows pulse blaster to run the same
                    %sequence again by calling the runSequence function
                    stopSequence(h.pulseBlaster)

                    pause(h.forcedCollectionPauseTime)

                    % Add something for outliers (more than 3 std devs
                    % away) ***********

                    h.DAQ.takeData = false;                    
                    
                    if h.DAQ.dataPointsTaken ~= 0 
                        nPointsTaken = h.DAQ.dataPointsTaken;
%                         if h.odometer ~= 0
                            h.data.failedPoints(h.odometer,h.data.iteration(h.odometer)+1) = nFailedCollections;
%                         end                        
                        break
                    end

                    nFailedCollections = nFailedCollections + 1;
                    if nFailedCollections > 4
                        h.DAQ.takeData = false;
                        error('No data points taken 5 times, aborting collection attempts.')
                    else
                        warning('No data points taken. Retrying collection (%d).',nFailedCollections)
%                         pause(.1)
                    end

                end             

               if strcmp(h.DAQ.differentiateSignal,'on')
                  dataOut{1}(1) = h.DAQ.handshake.UserData.reference;
                  dataOut{1}(2) = h.DAQ.handshake.UserData.signal;
                  if strcmp(h.DAQ.dataAcquirementMethod,'Voltage')
                      dataOut{1}(1:2) = dataOut{1}(1:2) ./ h.DAQ.dataPointsTaken;
                  end
               else
                  %Takes data and puts it in the current iteration spot for this
                  %data point
                  dataOut{1} = readData(h.DAQ);
               end

            case 'scmos'
               %Takes image using the camera and the current settings
               [dataOut,frameStacks] = takeImage(h.hamm);

               %Adds frame stacks to data output
               for ii = 1:numel(frameStacks)
                  dataOut{end+1} = frameStacks{ii}; %#ok<AGROW>
               end
         end
      end

      function h = plotData(h,dataIn,plotName,varargin)
         %4th argument is y axis label for 1D plot

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

         if isvector(dataIn) %1D
            if numel(h.scan.nSteps) ~= 1
               error('plotData function only works for 1D data when there is only 1 scan dimension')
            end
            if numel(dataIn) ~= h.scan.nSteps
               error(strcat('plotData function only works for 1D data when the number',...
                  ' of data points in the scan matches the number of data points given in argument 2'))
            end

            if isa(h.scan.bounds,'cell') %REALLY BAD FIX HERE******
                %x axis isn't the same. Assumed to be different plot entirely
            if (~h.useManualSteps && any(h.plots.(plotName).axes.XLim ~= h.scan.bounds{1})) || ...
                  (h.useManualSteps && h.plots.(plotName).dataDisplay.XData ~= h.manualSteps)
               replot = true;
            end

            if replot
               %Creates x axis from manual steps or from scan settings
               if h.useManualSteps
                  xAxis = h.manualSteps;
               else
                  xAxis = h.scan.bounds{1}(1):h.scan.stepSize:h.scan.bounds{1}(2);
               end

               %Creates the actual plot as a line
               h.plots.(plotName).dataDisplay = plot(h.plots.(plotName).axes,xAxis,dataIn);

               %Add x and, optionally, y labels
               xlabel(h.plots.(plotName).axes,h.scan.parameter)
               if nargin > 3
                  ylabel(h.plots.(plotName).axes,varargin{1})
               end
            else
               h.plots.(plotName).dataDisplay.YData = dataIn;
            end
            else
                %x axis isn't the same. Assumed to be different plot entirely
            if (~h.useManualSteps && any(h.plots.(plotName).axes.XLim ~= h.scan.bounds)) || ...
                  (h.useManualSteps && h.plots.(plotName).dataDisplay.XData ~= h.manualSteps)
               replot = true;
            end

            if replot
               %Creates x axis from manual steps or from scan settings
               if h.useManualSteps
                  xAxis = h.manualSteps;
               else
                  xAxis = h.scan.bounds(1):h.scan.stepSize:h.scan.bounds(2);
               end

               %Creates the actual plot as a line
               h.plots.(plotName).dataDisplay = plot(h.plots.(plotName).axes,xAxis,dataIn);

               %Add x and, optionally, y labels
               xlabel(h.plots.(plotName).axes,h.scan.parameter)
               if nargin > 3
                  ylabel(h.plots.(plotName).axes,varargin{1})
               end
            else
               h.plots.(plotName).dataDisplay.YData = dataIn;
            end
            end

            

         else %image

            %Different image bounds
            if ~replot && (size(dataIn,1) ~= h.plots.(plotName).dataDisplay.YData(2) || ...
                  size(dataIn,2) ~= h.plots.(plotName).dataDisplay.XData(2))
               replot = true;
            end

            if replot
               h.plots.(plotName).dataDisplay = imagesc(h.plots.(plotName).axes,dataIn);
               h.plots.(plotName).axes.Colormap = cmap2gray(h.plots.(plotName).axes.Colormap);
               h.plots.(plotName).colorbar = colorbar(h.plots.(plotName).axes);
            else
                h.plots.(plotName).dataDisplay.CData = dataIn;
            end

            
         end
%          if replot
%             %Sets the plot title to include the given plotName and any scan
%             %notes
%             if ~isempty(h.scan) && ~isempty(h.scan.notes) && ~strcmp(h.scan.notes,'')
%                title(h.plots.(plotName).axes,strcat(plotTitle,' (',h.scan.notes,')'))
%             else
%                title(h.plots.(plotName).axes,plotTitle)
%             end
%          else
%             h.plots.(plotName).dataDisplay.CData = dataIn;
%          end

      end

      function c = findContrast(h,contrastFunction,iterationType)
         %Obtains the contrast
         %Only works for 1x1 cell for each data point

         %Defaults to contrast of reference - signal / reference
         if isempty(contrastFunction)
            contrastFunction = @(rs)(rs(1)-rs(2))/rs(1);
         end

         %Pulls what data should be used then manipulates it using the
         %number of iterations if relevant
         switch lower(iterationType)
            case {'new','current','recent'}
               chosenData = cellfun(@(x)x{1},h.data.current,'UniformOutput',false);
            case {'previous','prior','old'}
               chosenData = cellfun(@(x)x{1},h.data.previous,'UniformOutput',false);
               chosenData = cellfun(@(x,y)x./(y-1),chosenData,num2cell(h.data.iteration),'UniformOutput',false);
            case {'average','total',[],''}
               chosenData = cellfun(@(x,y,z)(x{1}+y{1})./z,h.data.current,h.data.previous,num2cell(h.data.iteration),'UniformOutput',false);
            otherwise
               error('2nd argument''s structure''s iterationType must be new, old, or average ')
         end

         %Apply contrast function to the chosen data
         c = cellfun(contrastFunction,chosenData);

         if any(~isnan(c))
            c(isnan(c)) = mean(c(~isnan(c)));
         else
             c(1:end) = 0;
         end
      end

      function checkInstrument(h,instrumentName,varargin)
         %Checks if designated object is present and, if it is, whether it
         %is connected
         if nargin == 3
            acquisitionType = varargin{1};
            if ~ismember(instrumentName,h.instrumentClasses)
               error('%s object required to perform ''%s'' data acquisition',instrumentName,acquisitionType)
            end
            if ~h.instrumentCells{strcmp(h.instrumentClasses,instrumentName)}.connected
               error('%s must be connected to perform ''%s'' data acquisition',instrumentName,acquisitionType)
            end
         else
            if ~ismember(instrumentName,h.instrumentClasses)
               error('%s object required to perform scan on %s',instrumentName,instrumentName)
            end
            if ~h.instrumentCells{strcmp(h.instrumentClasses,instrumentName)}.connected
               error('%s must be connected to perform scan on %s',instrumentName,instrumentName)
            end
         end
      end

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
          properIdentifier = instrumentType.giveProperIdentifier(instrumentName);
          instrumentLocation = findInstrument(h,properIdentifier);
          if ~any(instrumentLocation)
              s = [];
          else
            s = h.instrumentCells{instrumentLocation};
          end
      end

      function h = setInstrumentVal(h,instrumentProperName,val)
         instrumentLocation = findInstrument(h,instrumentProperName);
         if sum(instrumentLocation) == 0
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
         s = getInstrumentVal(h,'hamm');
      end
      function h = set.hamm(h,val)
         h = setInstrumentVal(h,'hamm',val);  
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

      
   end
end