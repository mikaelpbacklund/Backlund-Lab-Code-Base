classdef stage < instrumentType

   properties (SetAccess = {?stage ?instrumentType}, GetAccess = public)
      controllerInfo
      pathObject
      SNList
      modelList
      handshake      
      axisSum
      locationsRecord
   end

   properties
      maxConnectionAttempts = 5;
      ignoreWait = false;
      tolerance = .1; %Overriden by standard deviations if it is non-zero (overriden by default)
      toleranceStandardDeviations = 2.5; %Overrides hard set tolerance if non-zero
      checkTolerance = false;
      pauseTime = .05;
      resetToMidpoint = true; %If true, fine axis resets to midpoint. If false, it resets to max/min depending on movement direction
      maxRecord = 1000;
      numberRecordsErased = 100;
      absoluteTolerance = false;
   end

   methods
      %Methods from PI can be found in their software package that must be
      %downloaded to programfiles(x86)

      function delete(h)
         %Before deleting, disconnect all stages
         h = disconnect(h); %#ok<NASGU>
      end

      function h = stage(configFileName)
         %Creates stage object

         if nargin < 1
            error('Config file name required as input')
         end

         %Adds drivers for PI stage
         addpath(getenv('PI_MATLAB_DRIVER'))

         %Loads config file and checks relevant field names
         configFields = {'controllerInfo','identifier'};
         commandFields = {};
         numericalFields = {};
         h = loadConfig(h,configFileName,configFields,commandFields,numericalFields);

         %Set identifier as given name
         h.identifier = configFileName;
      end

      function h = connect(h)
         %Creates connection to all stage models given by config file

         if h.connected
            warning('Stage is already connected')
            return
         end

         %This try/catch is to ensure proper status of h.connected in the event of failure
         try

            %Checks defaults of the following settings then
            %assigns them to corresponding properties
            s = checkSettings(h,fieldnames(h.defaults));
            h = instrumentType.overrideStruct(h,s);

            h.identifier = 'stage';%Label for stage

            %Loop for potential failures to connect
            nfails = 0;
            while true

               %Create PI_GCS_Controller object
               %evalc is used to suppress command window print inherent to function
               [~,h.pathObject] = evalc('PI_GCS_Controller');

               %Certain points may fail if connection is not established properly
               try

                  %Finds serial numbers and model
                  newConnections = EnumerateUSB(h.pathObject);
                  isPIStage = cellfun(@(a)strcmp(a(1:2),'PI'),newConnections);
                  newConnections = newConnections(isPIStage);
                  if isempty(newConnections) %Nothing obtained
                     error('No new possible connections found')
                  end
                  newModels = cellfun(@(a)a(4:8),newConnections,'UniformOutput',false);
                  newSNs = cellfun(@(a)findSN(a),newConnections,'UniformOutput',false);

                  %If no models/SNs, create models/SNs list
                  if isempty(h.modelList)
                     %For each new unique serial number, create connection and store in handshake
                     for jj = 1:numel(newSNs)
                        h.handshake{end+1} = ConnectUSB(h.pathObject,newSNs{jj});
                     end
                     h.modelList = newModels;
                     h.SNList = newSNs;
                  else
                     %Check if already on list
                     notOnList = ~contains(newModels,h.modelList);
                     if ~any(notOnList)
                        error('No new models found')
                     end
                     newModels = newModels(notOnList);
                     newSNs = newSNs(notOnList);

                     %For each new unique serial number, create connection and store in handshake
                     for jj = 1:numel(newSNs)
                        h.handshake{end+1} = ConnectUSB(h.pathObject,newSNs{jj});
                     end

                     %Update list of models and serial numbers
                     h.modelList(end+1:end+numel(newModels)) = newModels;
                     h.SNList(end+1:end+numel(newSNs)) = newSNs;
                  end

                  %For every axis to be controlled
                  for jj = 1:numel(h.controllerInfo)
                     %If there is already a known serial number, skip axis
                     if isfield(h.controllerInfo(jj),'serialNumber') && ~isempty(h.controllerInfo(jj).serialNumber)
                        continue
                     end

                     %Finds if any of the new models match axis' model
                     matchingModel = cellfun(@(x)strcmpi(h.controllerInfo(jj).model,x),newModels);

                     %If there is a matching connection, add serial number
                     %and handshake location to controllerInfo
                     if any(matchingModel)
                        h.controllerInfo(jj).serialNumber = str2double(newSNs{matchingModel});
                        %Handshake location must be based on total list not just new ones
                        h.controllerInfo(jj).handshakeNumber = find(cellfun(@(x)strcmpi(h.controllerInfo(jj).model,x),h.modelList));
                     end
                  end

                  %If not all rows find a corresponding serial number, retry
                  if any(cellfun('isempty',{h.controllerInfo.handshakeNumber}))
                     error('Not all controllers connected')
                  end

                  break %ends loop upon successful connection

               catch ME
                  nfails = nfails+1;%Increment failed attempts

                  %If number of fails hits max attempts, throw error, otherwise throw warning
                  if nfails >= h.maxConnectionAttempts
                     warning('Not all specified stage controllers were connected. Last error:')
                     rethrow(ME)
                  end
                  warning(ME.message)
                  fprintf('Not all specified stage controllers were connected (%d times). Retrying...\n',nfails)

                  %Gets rid of any handshakes that didn't properly connect
                  extraHandshakes = numel(h.handshake) - numel(h.SNList);
                  if extraHandshakes > 0
                     for jj = 1:extraHandshakes
                        h.handshake{end}.CloseConnection
                        h.handshake(end) = [];
                     end
                  end
                  pause(.5) %Rapid connection attempts fail, pause is required between attempts
               end
            end

            %Finds unique spatial axes and creates entries in axisSum property
            uniqueAxes = unique({h.controllerInfo.axis});
            h.axisSum = cell(numel(uniqueAxes),2);
            h.axisSum(:,1) = uniqueAxes;

            %Marks stage as connected (necessary for toggleAxis to work)
            h.connected = true;

            %Turn on all axes
            for ii = 1:numel(h.controllerInfo)
               h = toggleAxis(h,ii,'on');
            end

            %If connection fails, disconnect all controllers
         catch ME
            h.connected = true; %"Tricks" disconnect function into actually disconnecting
            h = disconnect(h);%#ok<NASGU>
            rethrow(ME)
         end

         function  PISerialNumber = findSN(identificationString)
            %Short function to locate serial numbers based on format for PI
            SNLocation = strfind(identificationString,' SN ');
            PISerialNumber = identificationString(SNLocation+4:end-1);
         end

      end

      function h = toggleAxis(h,infoRow,toggleStatus)
         %Turns a given axis on or off

         %Turning it off is just deleting that axis
         if strcmpi(instrumentType.discernOnOff(toggleStatus),'off')
            h.handshake{h.controllerInfo(infoRow).handshakeNumber}.Destroy
            return
         end

         %Turns on given axis. Also acquires its limits and current position
         currentInfo = h.controllerInfo(infoRow);

         %Activates servo for axis
         h.handshake{currentInfo.handshakeNumber} .SVO(currentInfo.internalAxisNumber,1)

         %Get max and min intrinsic limits from the stage
         h.controllerInfo(infoRow).intrinsicLimits(1) = h.handshake{currentInfo.handshakeNumber} .qTMN(currentInfo.internalAxisNumber);
         h.controllerInfo(infoRow).intrinsicLimits(2) = h.handshake{currentInfo.handshakeNumber} .qTMX(currentInfo.internalAxisNumber);

         %Converts to appropriate units
         h.controllerInfo(infoRow).intrinsicLimits = h.controllerInfo(infoRow).intrinsicLimits .* currentInfo.conversionFactor;

         %Finds total range of movement in micrometers for each stage and axis
         h.controllerInfo(infoRow).intrinsicRange = h.controllerInfo(infoRow).intrinsicLimits(2) - h.controllerInfo(infoRow).intrinsicLimits(1);

         %Buffers edges of possible movement slightly to prevent errors
         h.controllerInfo(infoRow).limits(1) = h.controllerInfo(infoRow).intrinsicLimits(1) + h.controllerInfo(infoRow).intrinsicRange*.03;
         h.controllerInfo(infoRow).limits(2) = h.controllerInfo(infoRow).intrinsicLimits(2) - h.controllerInfo(infoRow).intrinsicRange*.03;

         %Computes midpoint of range
         h.controllerInfo(infoRow).midpoint = h.controllerInfo(infoRow).intrinsicLimits(1) + h.controllerInfo(infoRow).intrinsicRange/2;

         %Sets current error compensation to 0. Will only be non-zero if checkTolerance is on and spatial axis location
         %is not within tolerance when checked
         h.controllerInfo(infoRow).errorCompensation = 0;

         %Gets current information regarding this axis
         h = getStageInfo(h,infoRow);

         %Sets target location to current location
         h.controllerInfo(infoRow).targetLocation = h.controllerInfo(infoRow).location;

         %Extra compensation needed for axis to achieve target location if
         %precision of coarse stage is not good enough
         h.controllerInfo(infoRow).extraCompensation = 0;

         %Sets locationDeviation for this axis based on checking current location 20 times
         h = findLocationDeviance(h,h.controllerInfo(infoRow).axis,20,h.controllerInfo(infoRow).grain);
      end

      function h = disconnect(h)
         %Deletes all connections and records

         if ~h.connected,    return;   end

         %Deletes location records if present
         if ~isempty(h.locationsRecord),    h.locationsRecord = [];    end

         %Destroys (PI function) then deletes all handshake connections
         if ~isempty(h.handshake)
            for ii = 1:size(h.handshake,1)
               h.handshake{ii}.Destroy
            end
            h.handshake = [];
         end

         %Removes path object controller and sets connected to off
         h.pathObject = [];
         h.connected = false;
      end

      function h = getStageInfo(h,axisRows)
         %Pings handshake to update current information
         checkConnection(h)

         %If it is a string, find all controllers for that spatial axis and
         %convert to double
         if isa(axisRows,'string') || isa(axisRows,'char')
            [h,axisRows] = findAxisRow(h,axisRows,["coarse","fine"]);
         end

         for infoRow = axisRows
            currentInfo = h.controllerInfo(infoRow);

            %Obtains current position of the stage
            h.controllerInfo(infoRow).location = h.handshake{currentInfo.handshakeNumber} .qPOS(currentInfo.internalAxisNumber);

            %Conversion to correct units
            h.controllerInfo(infoRow).location = h.controllerInfo(infoRow).location .* currentInfo.conversionFactor;

            %Swaps sign if needed
            if h.controllerInfo(infoRow).invertLocation
               h.controllerInfo(infoRow).location = -h.controllerInfo(infoRow).location;
            end
         end

         %Adds current location to record
         currentLocation = {h.controllerInfo.location};
         if any(cellfun(@(x)isempty(x),currentLocation))
            %If axis position hasn't been acquired yet
            [currentLocation{cellfun(@(x)isempty(x),currentLocation)}] = deal(0);
         end
         h.locationsRecord(end+1,:) = cell2mat(currentLocation)';

         %If the location record is too large, delete the first 100 entries or all
         %the entries except 1 if the list is less than 100 long
         if size(h.locationsRecord,1) > h.maxRecord
            if h.notifications
               fprintf(['Locations record exceeds maximum of %d data points as set by'...
                  ' h.maxRecord\nRemoving the earliest 100 points\n'],h.maxRecord)
            end
            if h.maxRecord < h.numberRecordsErased
               h.locationsRecord(1:end-1,:) = [];
            else
               h.locationsRecord(1:h.numberRecordsErased,:) = [];
            end
         end

         %Calculates the sum for each spatial axis
         for ii = 1:size(h.axisSum,1)
            spatialAxis = h.axisSum{ii,1};
            designatedAxes = cellfun(@(a)strcmpi(spatialAxis,a(end)),{h.controllerInfo.axis});
            h.axisSum{ii,2} = sum(cell2mat({h.controllerInfo(designatedAxes).location}));
         end
      end

      function h = directMove(h,axisName,newTarget,varargin)
         %Moves the stage without checking limits or other axes
         %newTarget is desired absolute position
         %4th input is coarse/fine designation
         %Note: errorCompensation field modifies target set in directMove

         checkConnection(h)

         %Finds the axis row corresponding to the name and grain (if given)
         if nargin < 4
            [h,axisRow] = findAxisRow(h,axisName);
         else
            [h,axisRow] = findAxisRow(h,axisName,varargin{1});
         end

         %Checks if new target location is within the bounds of the axis
         if newTarget > h.controllerInfo(axisRow).limits(2) || newTarget < h.controllerInfo(axisRow).limits(1)
            if nargin < 4
               error('%s stage boundary reached. Attempted to move to %.3f\n',axisName,newTarget)
            else
               error('%s %s stage boundary reached. Attempted to move to %.3f\n',varargin{1},axisName,newTarget)
            end
         end

         %Finds amount of relative movement to display in printout later
         relativeMovement = newTarget - h.controllerInfo(axisRow).targetLocation;

         %Sets target location to the new target and error compensation
         h.controllerInfo(axisRow).targetLocation = newTarget + h.controllerInfo(axisRow).errorCompensation;

         %Get shorthand for use later
         currentInfo = h.controllerInfo(axisRow);
         handshakeRow = currentInfo.handshakeNumber;

         %Conversion to correct units
         newTarget = newTarget / currentInfo.conversionFactor;

         %Inverts location about 0 if necessary
         if currentInfo.invertLocation,    newTarget = -newTarget;   end

         %Performs absolute movement to target
         h.handshake{handshakeRow} .MOV(currentInfo.internalAxisNumber,newTarget);

         %Pauses if enabled
         if ~h.ignoreWait,    pause(h.pauseTime);    end

         n = 0;
         while true
            %If ignore wait is on, do not wait for reported finished movement
            if h.ignoreWait,     break;    end

            %If the stage is reporting that it isn't moving, end this loop
            if ~h.handshake{handshakeRow} .IsMoving(currentInfo.internalAxisNumber)
               break
            end

            pause(.001)

            %Counter to ensure stage does not get "stuck" reporting movement forever
            n = n+1;
            if n == 1000
               if master.notifications
                  fprintf('%s stage not reporting finished movement after 1 second. Halting movement\n',axisLabel)
               end
               h.handshake{handshakeRow} .HLT(currentInfo.internalAxisNumber)
               pause(.001)
               break
            end

         end

         %Updates stage information post-movement
         h = getStageInfo(h,axisRow);

         %Prints out new stage information
         if nargin > 3
            printOut(h,sprintf("%s %s moved %.3f μm to %.3f μm", varargin{1},axisName,relativeMovement,h.controllerInfo(axisRow).location))
         else
            printOut(h,sprintf("%s moved %.3f μm to %.3f μm",axisName,relativeMovement,h.controllerInfo(axisRow).location))
         end

      end

      function h = relativeMove(h,spatialAxis,targetMovement)
         %Moves relative to current location
         %Uses fine stage when possible, coarse stage when necessary
         checkConnection(h)


         try
            %Works if only 1 axis per spatial axis (no grain)
            [h,infoRows] = findAxisRow(h,spatialAxis);
            targetLocation = targetMovement + h.controllerInfo(infoRows).targetLocation;
         catch
            %Works for multiple spatial axes
            [h,infoRows] = findAxisRow(h,spatialAxis,["coarse","fine"]);
            targetLocation = targetMovement;
            for ii = infoRows
               targetLocation = targetLocation + h.controllerInfo(ii).targetLocation;
            end
         end

         %Moves to absolute location of target
         %Saves on a lot of code by routing it through that function
         h = absoluteMove(h,spatialAxis,targetLocation);
      end

      function h = absoluteMove(h,spatialAxis,targetLocation)
         %Moves to new absolute location along spatial axis
         %Uses fine stage when possible, coarse stage when necessary
         checkConnection(h)

         try
            %Only works for one spatial axis, not coarse/fine
            h = directMove(h,spatialAxis,targetLocation);
            %Checks if current location is within tolerance of the target if enabled
            h = toleranceCheck(h,spatialAxis);
            return
         catch
         end

         %Get information about what connections should be used
         [h,fineRow] = findAxisRow(h,spatialAxis,'fine');
         [h,coarseRow] = findAxisRow(h,spatialAxis,'coarse');
         sumRow = strcmpi(spatialAxis,h.axisSum(:,1));

         %Finds relative movement to determine if move would be outside fine bounds
         relativeTarget = targetLocation - (h.controllerInfo(fineRow).targetLocation + h.controllerInfo(coarseRow).targetLocation);

         %If there is no change in location, print that then end function
         if relativeTarget == 0
            printOut(h,sprintf('%s axis already at %.3f',spatialAxis,targetLocation))
            return
         end

         %Checks if coarse movement is required. If it is, performs fine reset, then moves coarse to compensate for fine
         %and adds the new target
         if relativeTarget + h.controllerInfo(fineRow).targetLocation >= h.controllerInfo(fineRow).limits(2) || ...
               relativeTarget + h.controllerInfo(fineRow).targetLocation <= h.controllerInfo(fineRow).limits(1)

            %Gets location for fine stage when reset
            if ~h.resetToMidpoint
               %Move stage to min/max if target is positive/negative to allow for more
               %consecutive movements without a reset
               if targetMovement >  0
                  resetLocation = 'minimum';
               else
                  resetLocation = 'maximum';
               end
            else
               %Reset fine stage to midpoint
               resetLocation = 'midpoint';
            end

            %Resets fine stage without changing coarse and gives the coarseCompensation as output
            [h,coarseCompensation] = fineReset(h,spatialAxis,resetLocation,false);

            %Calculates new target location for the coarse stage
            coarseTarget = h.controllerInfo(coarseRow).targetLocation + coarseCompensation + relativeTarget;

            %Moves coarse stage to new location
            h = directMove(h,spatialAxis,coarseTarget,'coarse');

         else %Fine movement only

            %Finds absolute target location for fine stage then directly move there
            %Adds extra compensation if already present
            fineTarget = relativeTarget + h.controllerInfo(fineRow).targetLocation;
            h = directMove(h,spatialAxis,fineTarget+h.controllerInfo(fineRow).extraCompensation,'fine');

         end

         %Checks if current location is within tolerance of the target if enabled
         h = toleranceCheck(h,spatialAxis);

         h = getStageInfo(h,spatialAxis);

         %Prints current axis total
         printOut(h,sprintf('Axis total: %.3f μm',h.axisSum{sumRow,2}))
      end

      function [h,varargout] = fineReset(h,spatialAxis,minMaxMid,compensateForCoarse)
         %Sets fine axis back to min/max/mid depending on input
         %Either compensates for coarse directly, or outputs calculated coarse compensation
         checkConnection(h)

         [h,fineRow] = findAxisRow(h,spatialAxis,'fine');
         [h,coarseRow] = findAxisRow(h,spatialAxis,'coarse');

         %Updates current information on the coarse and fine stage of this axis
         h = getStageInfo(h,[fineRow,coarseRow]);

         %Finds absolute target location based on minMaxMid input. For min and max, an additional 2% buffer is given to
         %prevent going over bounds particularly in a tolerance check
         switch minMaxMid
            case {'minimum','min','low'}
               fineTarget = h.controllerInfo(fineRow).limits(1) + .02*h.controllerInfo(fineRow).intrinsicRange;

            case {'maximum','max','high'}
               fineTarget = h.controllerInfo(fineRow).limits(2) - .02*h.controllerInfo(fineRow).intrinsicRange;

            case {'midpoint','mid','middle'}
               fineTarget = h.controllerInfo(fineRow).midpoint;
         end

         %If the fine target is within 5% (based on range) of its current location, do not perform reset and output
         %0 for coarse compensation. Fine resets are only really useful if they move the stage significantly, so this
         %reduces redundant movements
         percentageOff = abs(fineTarget - h.controllerInfo(fineRow).targetLocation) / h.controllerInfo(fineRow).intrinsicRange;
         if percentageOff < .05
            printOut(h,'Fine reset aborted. Fine location already within 5% of its target')
            if ~compensateForCoarse,    varargout{1} = 0;    end
            return
         end

         %Calculates how far the fine stage will be moving. Used to calculate coarse compensation
         relativeFineMovement = fineTarget - h.controllerInfo(fineRow).targetLocation;

         %Moves the fine stage to calculated location
         h = directMove(h,spatialAxis,fineTarget,'fine');

         %If enabled, move coarse stage to compensate for fine movement. Otherwise, output how much coarse stage should
         %move by to do that compensation
         if compensateForCoarse
            h = directMove(h,spatialAxis,h.controllerInfo(coarseRow).targetLocation - relativeFineMovement,'coarse');
         else
            varargout{1} = -relativeFineMovement;
         end

         %Checks tolerance if enabled
         h = toleranceCheck(h,spatialAxis);

      end

      function h = toleranceCheck(h,spatialAxis)
         %Checks if current location is within tolerance μm of target location
         %This is the only function that will change the errorCompensation field for controllerInfo
         %It is solely used to change the target of the fine stage such that the location is within tolerance after
         %moving to what should be the target area

         %If set to not check tolerance or tolerance is 0, end function
         if ~h.checkTolerance || (h.tolerance == 0 && h.absoluteTolerance) ||...
                 (h.toleranceStandardDeviations == 0 && ~h.absoluteTolerance)
            return
         end

         try
            %Works if only 1 axis per spatial axis (no grain)
            [h,infoRows] = findAxisRow(h,spatialAxis);
         catch
            %Works for fine and coarse grain for spatial axes
            [h,infoRows] = findAxisRow(h,spatialAxis,["coarse","fine"]);
         end         

         %Finds tolerance based on either absolute number or number of standard deviations given for each axis
         if ~isempty(nonzeros(h.toleranceStandardDeviations))
            totalTolerance = 0;
            for ii = infoRows
               totalTolerance = totalTolerance + (h.toleranceStandardDeviations*h.controllerInfo(ii).locationDeviation);
            end
         elseif ~isempty(nonzeros(h.absoluteTolerance))
            totalTolerance = h.absoluteTolerance;
         else
            error('Either absoluteTolerance or toleranceStandardDeviations must be nonzero')
         end

         loopCounter = 0;
         while true
            loopCounter = loopCounter + 1;            

            targetLocation = 0;
            trueLocation = 0;
            for ii = infoRows
               targetLocation = targetLocation + h.controllerInfo(ii).targetLocation;
               trueLocation = trueLocation + h.controllerInfo(ii).location;
            end

            if abs(trueLocation - targetLocation) < totalTolerance
                fprintf('tolerance loops used: %d\n',loopCounter)
               return
            end

            %Every 50 ms, add compensation to finest stage based on difference between true and target
            if mod(loopCounter,50) == 0
               h.controllerInfo(infoRows(end)).errorCompensation = h.controllerInfo(infoRows(end)).errorCompensation + (trueLocation - targetLocation);
            end

            %Every 10 ms, jostle stage
            if mod(loopCounter,10) == 0
               oldIgnoreWait = h.ignoreWait;
               h.ignoreWait = true; %Disable wait for jostling
               for ii = infoRows
                  %Moves stage 1 nm then back again after 1 ms
                  h = directMove(h,spatialAxis,h.controllerInfo(ii).targetLocation + .001,h.controllerInfo(ii).grain);
                  pause(.01)
                  h = directMove(h,spatialAxis,h.controllerInfo(ii).targetLocation,h.controllerInfo(ii).grain);
               end
               h.ignoreWait = oldIgnoreWait; %Set back to previous value
            end

            if loopCounter > 100 %Hard cap of 1 second
               error('Could not get %s axis within tolerance',spatialAxis)
            end

            %Wait 1 ms on failed tolerance check
            pause(.001)

         end
      end

      function [h,varargout] = findLocationDeviance(h,spatialAxis,varargin)
         %Outputs vector of deviation from target location of the stage
         %3rd argument is number of reps
         %4th argument is grain of axis (required if more than 1 on that spatial axis)

         %Default to 100 repetitions if not set by user
         if nargin > 2 || isempty(varargin{1})
            nReps = varargin{1};
         else
            nReps = 100;
         end

         %If only 1 axis on that spatial axis, grain is unneeded
         if nargin > 3
            [h,axisRow] = findAxisRow(h,spatialAxis,varargin{2});
         else
            [h,axisRow] = findAxisRow(h,spatialAxis);
         end

         locationDeviance = zeros(1,nReps); %Preallocation

         %Repeatedly query stage location and compare to target location
         tic
         for ii = 1:nReps
            h = getStageInfo(h,axisRow);
            locationDeviance(ii) = h.controllerInfo(axisRow).location - h.controllerInfo(axisRow).targetLocation;
         end
         %Outputs average time per data point as 3rd optional output
         varargout{3} = toc/nReps;

         %Get mean location 2nd optional output
         varargout{2} = mean(locationDeviance);

         %Output list of location deviations as 1st optional output
         varargout{1} = locationDeviance;

         %Sets location deviation for that axis to the found standard deviation
         h.controllerInfo(axisRow).locationDeviation = std(locationDeviance);
      end

      function [h,axisRows] = findAxisRow(h,spatialAxis,varargin)
         %Finds the row in controllerInfo corresponding to the spatial axis name
         %If multiple rows exist, use 3rd argument to determine order of output

         %Determine the correct axis to move
         allSpatialAxes = strcmpi(spatialAxis,{h.controllerInfo.axis});

         %If only 1 axis matching spatial axis, that is output
         if sum(allSpatialAxes) < 2
            axisRows = find(allSpatialAxes);
            return
         end

         %If multiple connections exist with that axis name, check for matching grain (coarse/fine)
         if nargin < 3
            error('Multiple connections exist for %s but no designation of grain (e.g. coarse/fine) was given',spatialAxis)
         end

         %Converts input into string array
         grainStrings = convertCharsToStrings(varargin{1});

         %Preallocation
         axisRows = zeros(1,numel(grainStrings));

         %For each grain string, find corresponding row for matching grains
         %For those matching both spatial axes and grain axes, output row number
         for ii = 1:numel(grainStrings)
            grainRow = strcmpi(grainStrings(ii),{h.controllerInfo.grain});
            grainRow = find(grainRow & allSpatialAxes);
            if numel(grainRow) > 1
               error('2 connections exist for %s %s. Only 1 connection per axis/grain combination allowed',grainStrings(ii),spatialAxis)
            end
            axisRows(ii) = grainRow;
         end

      end
   end

end