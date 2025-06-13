classdef stage < instrumentType
   %stage - Controls and manages stage devices
   %
   % Features:
   %   - Position control
   %   - Speed control
   %   - Limit detection
   %   - Status monitoring
   %
   % Usage:
   %   stage = stage('configFileName.json');
   %   stage.connect();
   %   stage.moveTo(100);
   %   pos = stage.getPosition();
   %
   % Dependencies:
   %   - JSON configuration file with stage settings

   properties (Dependent)
      % Properties that can be modified by the user
      position           % Current position
      speed             % Movement speed
      acceleration      % Movement acceleration
   end

   properties (SetAccess = {?stage ?instrumentType}, GetAccess = public)
      % Properties managed internally by the class
      manufacturer      % Stage manufacturer
      model            % Stage model
      maxPosition      % Maximum position
      minPosition      % Minimum position
      maxSpeed         % Maximum speed
      minSpeed         % Minimum speed
      handshake        % Stage connection handle
      controllerInfo
      pathObject
      SNList
      modelList 
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
      function obj = stage(configFileName)
         %stage Creates a new stage instance
         %
         %   obj = stage(configFileName) creates a new stage instance
         %   using the specified configuration file.
         %
         %   Throws:
         %       error - If configFileName is not provided
         
         if nargin < 1
            error('stage:MissingConfig', 'Config file name required as input')
         end

         %Adds drivers for PI stage
         addpath(getenv('PI_MATLAB_DRIVER'))

         %Loads config file and checks relevant field names
         configFields = {'manufacturer','model','maxPosition','minPosition','maxSpeed','minSpeed'};
         commandFields = {};
         numericalFields = {};
         obj = loadConfig(obj,configFileName,configFields,commandFields,numericalFields);

         %Set identifier as given name
         obj.identifier = configFileName;
      end
      
      function obj = connect(obj)
         %connect Establishes connection with the stage
         %
         %   obj = connect(obj) connects to the stage and initializes
         %   settings.
         %
         %   Throws:
         %       error - If stage is already connected
         
         if obj.connected
            error('stage:AlreadyConnected', 'Stage is already connected')
         end

         %This try/catch is to ensure proper status of obj.connected in the event of failure
         try

            %Checks defaults of the following settings then
            %assigns them to corresponding properties
            s = checkSettings(obj,fieldnames(obj.defaults));
            obj = instrumentType.overrideStruct(obj,s);

            obj.identifier = 'stage';%Label for stage

            %Loop for potential failures to connect
            nfails = 0;
            while true

               %Create PI_GCS_Controller object
               %evalc is used to suppress command window print inherent to function
               [~,obj.pathObject] = evalc('PI_GCS_Controller');

               %Certain points may fail if connection is not established properly
               try

                  %Finds serial numbers and model
                  newConnections = EnumerateUSB(obj.pathObject);
                  isPIStage = cellfun(@(a)strcmp(a(1:2),'PI'),newConnections);
                  newConnections = newConnections(isPIStage);
                  if isempty(newConnections) %Nothing obtained
                     error('No new possible connections found')
                  end
                  newModels = cellfun(@(a)a(4:8),newConnections,'UniformOutput',false);
                  newSNs = cellfun(@(a)findSN(a),newConnections,'UniformOutput',false);

                  %If no models/SNs, create models/SNs list
                  if isempty(obj.modelList)
                     %For each new unique serial number, create connection and store in handshake
                     for jj = 1:numel(newSNs)
                        obj.handshake{end+1} = ConnectUSB(obj.pathObject,newSNs{jj});
                     end
                     obj.modelList = newModels;
                     obj.SNList = newSNs;
                  else
                     %Check if already on list
                     notOnList = ~contains(newModels,obj.modelList);
                     if ~any(notOnList)
                        error('No new models found')
                     end
                     newModels = newModels(notOnList);
                     newSNs = newSNs(notOnList);

                     %For each new unique serial number, create connection and store in handshake
                     for jj = 1:numel(newSNs)
                        obj.handshake{end+1} = ConnectUSB(obj.pathObject,newSNs{jj});
                     end

                     %Update list of models and serial numbers
                     obj.modelList(end+1:end+numel(newModels)) = newModels;
                     obj.SNList(end+1:end+numel(newSNs)) = newSNs;
                  end

                  %For every axis to be controlled
                  for jj = 1:numel(obj.controllerInfo)
                     %If there is already a known serial number, skip axis
                     if isfield(obj.controllerInfo(jj),'serialNumber') && ~isempty(obj.controllerInfo(jj).serialNumber)
                        continue
                     end

                     %Finds if any of the new models match axis' model
                     matchingModel = cellfun(@(x)strcmpi(obj.controllerInfo(jj).model,x),newModels);

                     %If there is a matching connection, add serial number
                     %and handshake location to controllerInfo
                     if any(matchingModel)
                        obj.controllerInfo(jj).serialNumber = str2double(newSNs{matchingModel});
                        %Handshake location must be based on total list not just new ones
                        obj.controllerInfo(jj).handshakeNumber = find(cellfun(@(x)strcmpi(obj.controllerInfo(jj).model,x),obj.modelList));
                     end
                  end

                  %If not all rows find a corresponding serial number, retry
                  if any(cellfun('isempty',{obj.controllerInfo.handshakeNumber}))
                     error('Not all controllers connected')
                  end

                  break %ends loop upon successful connection

               catch ME
                  nfails = nfails+1;%Increment failed attempts

                  %If number of fails hits max attempts, throw error, otherwise throw warning
                  if nfails >= obj.maxConnectionAttempts
                     warning('Not all specified stage controllers were connected. Last error:')
                     rethrow(ME)
                  end
                  warning(ME.message)
                  fprintf('Not all specified stage controllers were connected (%d times). Retrying...\n',nfails)

                  %Gets rid of any handshakes that didn't properly connect
                  extraHandshakes = numel(obj.handshake) - numel(obj.SNList);
                  if extraHandshakes > 0
                     for jj = 1:extraHandshakes
                        obj.handshake{end}.CloseConnection
                        obj.handshake(end) = [];
                     end
                  end
                  pause(.5) %Rapid connection attempts fail, pause is required between attempts
               end
            end

            %Finds unique spatial axes and creates entries in axisSum property
            uniqueAxes = unique({obj.controllerInfo.axis});
            obj.axisSum = cell(numel(uniqueAxes),2);
            obj.axisSum(:,1) = uniqueAxes;

            %Marks stage as connected (necessary for toggleAxis to work)
            obj.connected = true;

            %Turn on all axes
            for ii = 1:numel(obj.controllerInfo)
               obj = toggleAxis(obj,ii,'on');
            end

            %If connection fails, disconnect all controllers
         catch ME
            obj.connected = true; %"Tricks" disconnect function into actually disconnecting
            obj = disconnect(obj);%#ok<NASGU>
            rethrow(ME)
         end

         function  PISerialNumber = findSN(identificationString)
            %Short function to locate serial numbers based on format for PI
            SNLocation = strfind(identificationString,' SN ');
            PISerialNumber = identificationString(SNLocation+4:end-1);
         end

      end

      function obj = toggleAxis(obj,infoRow,toggleStatus)
         %Turns a given axis on or off

         %Turning it off is just deleting that axis
         if strcmpi(instrumentType.discernOnOff(toggleStatus),'off')
            obj.handshake{obj.controllerInfo(infoRow).handshakeNumber}.Destroy
            return
         end

         %Turns on given axis. Also acquires its limits and current position
         currentInfo = obj.controllerInfo(infoRow);

         %Activates servo for axis
         obj.handshake{currentInfo.handshakeNumber} .SVO(currentInfo.internalAxisNumber,1)

         %Get max and min intrinsic limits from the stage
         obj.controllerInfo(infoRow).intrinsicLimits(1) = obj.handshake{currentInfo.handshakeNumber} .qTMN(currentInfo.internalAxisNumber);
         obj.controllerInfo(infoRow).intrinsicLimits(2) = obj.handshake{currentInfo.handshakeNumber} .qTMX(currentInfo.internalAxisNumber);

         %Converts to appropriate units
         obj.controllerInfo(infoRow).intrinsicLimits = obj.controllerInfo(infoRow).intrinsicLimits .* currentInfo.conversionFactor;

         %Finds total range of movement in micrometers for each stage and axis
         obj.controllerInfo(infoRow).intrinsicRange = obj.controllerInfo(infoRow).intrinsicLimits(2) - obj.controllerInfo(infoRow).intrinsicLimits(1);

         %Buffers edges of possible movement slightly to prevent errors
         obj.controllerInfo(infoRow).limits(1) = obj.controllerInfo(infoRow).intrinsicLimits(1) + obj.controllerInfo(infoRow).intrinsicRange*.03;
         obj.controllerInfo(infoRow).limits(2) = obj.controllerInfo(infoRow).intrinsicLimits(2) - obj.controllerInfo(infoRow).intrinsicRange*.03;

         %Computes midpoint of range
         obj.controllerInfo(infoRow).midpoint = obj.controllerInfo(infoRow).intrinsicLimits(1) + obj.controllerInfo(infoRow).intrinsicRange/2;

         %Sets current error compensation to 0. Will only be non-zero if checkTolerance is on and spatial axis location
         %is not within tolerance when checked
         obj.controllerInfo(infoRow).errorCompensation = 0;

         %Gets current information regarding this axis
         obj = getStageInfo(obj,infoRow);

         %Sets target location to current location
         obj.controllerInfo(infoRow).targetLocation = obj.controllerInfo(infoRow).location;

         %Extra compensation needed for axis to achieve target location if
         %precision of coarse stage is not good enough
         obj.controllerInfo(infoRow).extraCompensation = 0;

         %Sets locationDeviation for this axis based on checking current location 20 times
         obj = findLocationDeviance(obj,obj.controllerInfo(infoRow).axis,20,obj.controllerInfo(infoRow).grain);
      end

      function obj = disconnect(obj)
         %disconnect Disconnects from the stage
         %
         %   obj = disconnect(obj) disconnects from the stage and cleans up
         %   resources.
         
         if ~obj.connected
            return;
         end
         
         %Deletes location records if present
         if ~isempty(obj.locationsRecord),    obj.locationsRecord = [];    end

         %Destroys (PI function) then deletes all handshake connections
         if ~isempty(obj.handshake)
            for ii = 1:size(obj.handshake,1)
               obj.handshake{ii}.Destroy
            end
            obj.handshake = [];
         end

         %Removes path object controller and sets connected to off
         obj.pathObject = [];
         obj.connected = false;
      end

      function obj = getStageInfo(obj,axisRows)
         %Pings handshake to update current information
         checkConnection(obj)

         %If it is a string, find all controllers for that spatial axis and
         %convert to double
         if isa(axisRows,'string') || isa(axisRows,'char')
            [obj,axisRows] = findAxisRow(obj,axisRows,["coarse","fine"]);
         end

         for infoRow = axisRows
            currentInfo = obj.controllerInfo(infoRow);

            %Obtains current position of the stage
            obj.controllerInfo(infoRow).location = obj.handshake{currentInfo.handshakeNumber} .qPOS(currentInfo.internalAxisNumber);

            %Conversion to correct units
            obj.controllerInfo(infoRow).location = obj.controllerInfo(infoRow).location .* currentInfo.conversionFactor;

            %Swaps sign if needed
            if obj.controllerInfo(infoRow).invertLocation
               obj.controllerInfo(infoRow).location = -obj.controllerInfo(infoRow).location;
            end
         end

         %Adds current location to record
         currentLocation = {obj.controllerInfo.location};
         if any(cellfun(@(x)isempty(x),currentLocation))
            %If axis position hasn't been acquired yet
            [currentLocation{cellfun(@(x)isempty(x),currentLocation)}] = deal(0);
         end
         obj.locationsRecord(end+1,:) = cell2mat(currentLocation)';

         %If the location record is too large, delete the first 100 entries or all
         %the entries except 1 if the list is less than 100 long
         if size(obj.locationsRecord,1) > obj.maxRecord
            if obj.notifications
               fprintf(['Locations record exceeds maximum of %d data points as set by'...
                  ' obj.maxRecord\nRemoving the earliest 100 points\n'],obj.maxRecord)
            end
            if obj.maxRecord < obj.numberRecordsErased
               obj.locationsRecord(1:end-1,:) = [];
            else
               obj.locationsRecord(1:obj.numberRecordsErased,:) = [];
            end
         end

         %Calculates the sum for each spatial axis
         for ii = 1:size(obj.axisSum,1)
            spatialAxis = obj.axisSum{ii,1};
            designatedAxes = cellfun(@(a)strcmpi(spatialAxis,a(end)),{obj.controllerInfo.axis});
            obj.axisSum{ii,2} = sum(cell2mat({obj.controllerInfo(designatedAxes).location}));
         end
      end

      function obj = directMove(obj,axisName,newTarget,varargin)
         %Moves the stage without checking limits or other axes
         %newTarget is desired absolute position
         %4th input is coarse/fine designation
         %Note: errorCompensation field modifies target set in directMove

         checkConnection(obj)

         %Finds the axis row corresponding to the name and grain (if given)
         if nargin < 4
            [obj,axisRow] = findAxisRow(obj,axisName);
         else
            [obj,axisRow] = findAxisRow(obj,axisName,varargin{1});
         end

         %Checks if new target location is within the bounds of the axis
         if newTarget > obj.controllerInfo(axisRow).limits(2) || newTarget < obj.controllerInfo(axisRow).limits(1)
            if nargin < 4
               error('%s stage boundary reached. Attempted to move to %.3f\n',axisName,newTarget)
            else
               error('%s %s stage boundary reached. Attempted to move to %.3f\n',varargin{1},axisName,newTarget)
            end
         end

         %Finds amount of relative movement to display in printout later
         relativeMovement = newTarget - obj.controllerInfo(axisRow).targetLocation;

         %Sets target location to the new target and error compensation
         obj.controllerInfo(axisRow).targetLocation = newTarget + obj.controllerInfo(axisRow).errorCompensation;

         %Get shorthand for use later
         currentInfo = obj.controllerInfo(axisRow);
         handshakeRow = currentInfo.handshakeNumber;

         %Conversion to correct units
         newTarget = newTarget / currentInfo.conversionFactor;

         %Inverts location about 0 if necessary
         if currentInfo.invertLocation,    newTarget = -newTarget;   end

         %Performs absolute movement to target
         obj.handshake{handshakeRow} .MOV(currentInfo.internalAxisNumber,newTarget);

         %Pauses if enabled
         if ~obj.ignoreWait,    pause(obj.pauseTime);    end

         n = 0;
         while true
            %If ignore wait is on, do not wait for reported finished movement
            if obj.ignoreWait,     break;    end

            %If the stage is reporting that it isn't moving, end this loop
            if ~obj.handshake{handshakeRow} .IsMoving(currentInfo.internalAxisNumber)
               break
            end

            pause(.001)

            %Counter to ensure stage does not get "stuck" reporting movement forever
            n = n+1;
            if n == 1000
               if master.notifications
                  fprintf('%s stage not reporting finished movement after 1 second. Halting movement\n',axisLabel)
               end
               obj.handshake{handshakeRow} .HLT(currentInfo.internalAxisNumber)
               pause(.001)
               break
            end

         end

         %Updates stage information post-movement
         obj = getStageInfo(obj,axisRow);

         %Prints out new stage information
         if nargin > 3
            printOut(obj,sprintf("%s %s moved %.3f μm to %.3f μm", varargin{1},axisName,relativeMovement,obj.controllerInfo(axisRow).location))
         else
            printOut(obj,sprintf("%s moved %.3f μm to %.3f μm",axisName,relativeMovement,obj.controllerInfo(axisRow).location))
         end

      end

      function obj = relativeMove(obj,spatialAxis,targetMovement)
         %Moves relative to current location
         %Uses fine stage when possible, coarse stage when necessary
         checkConnection(obj)


         try
            %Works if only 1 axis per spatial axis (no grain)
            [obj,infoRows] = findAxisRow(obj,spatialAxis);
            targetLocation = targetMovement + obj.controllerInfo(infoRows).targetLocation;
         catch
            %Works for multiple spatial axes
            [obj,infoRows] = findAxisRow(obj,spatialAxis,["coarse","fine"]);
            targetLocation = targetMovement;
            for ii = infoRows
               targetLocation = targetLocation + obj.controllerInfo(ii).targetLocation;
            end
         end

         %Moves to absolute location of target
         %Saves on a lot of code by routing it through that function
         obj = absoluteMove(obj,spatialAxis,targetLocation);
      end

      function obj = absoluteMove(obj,spatialAxis,targetLocation)
         %Moves to new absolute location along spatial axis
         %Uses fine stage when possible, coarse stage when necessary
         checkConnection(obj)

         try
            %Only works for one spatial axis, not coarse/fine
            obj = directMove(obj,spatialAxis,targetLocation);
            %Checks if current location is within tolerance of the target if enabled
            obj = toleranceCheck(obj,spatialAxis);
            return
         catch
         end

         %Get information about what connections should be used
         [obj,fineRow] = findAxisRow(obj,spatialAxis,'fine');
         [obj,coarseRow] = findAxisRow(obj,spatialAxis,'coarse');
         sumRow = strcmpi(spatialAxis,obj.axisSum(:,1));

         %Finds relative movement to determine if move would be outside fine bounds
         relativeTarget = targetLocation - (obj.controllerInfo(fineRow).targetLocation + obj.controllerInfo(coarseRow).targetLocation);

         %If there is no change in location, print that then end function
         if relativeTarget == 0
            printOut(obj,sprintf('%s axis already at %.3f',spatialAxis,targetLocation))
            return
         end

         %Checks if coarse movement is required. If it is, performs fine reset, then moves coarse to compensate for fine
         %and adds the new target
         if relativeTarget + obj.controllerInfo(fineRow).targetLocation >= obj.controllerInfo(fineRow).limits(2) || ...
               relativeTarget + obj.controllerInfo(fineRow).targetLocation <= obj.controllerInfo(fineRow).limits(1)

            %Gets location for fine stage when reset
            if ~obj.resetToMidpoint
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
            [obj,coarseCompensation] = fineReset(obj,spatialAxis,resetLocation,false);

            %Calculates new target location for the coarse stage
            coarseTarget = obj.controllerInfo(coarseRow).targetLocation + coarseCompensation + relativeTarget;

            %Moves coarse stage to new location
            obj = directMove(obj,spatialAxis,coarseTarget,'coarse');

         else %Fine movement only

            %Finds absolute target location for fine stage then directly move there
            %Adds extra compensation if already present
            fineTarget = relativeTarget + obj.controllerInfo(fineRow).targetLocation;
            obj = directMove(obj,spatialAxis,fineTarget+obj.controllerInfo(fineRow).extraCompensation,'fine');

         end

         %Checks if current location is within tolerance of the target if enabled
         obj = toleranceCheck(obj,spatialAxis);

         obj = getStageInfo(obj,spatialAxis);

         %Prints current axis total
         printOut(obj,sprintf('Axis total: %.3f μm',obj.axisSum{sumRow,2}))
      end

      function [obj,varargout] = fineReset(obj,spatialAxis,minMaxMid,compensateForCoarse)
         %Sets fine axis back to min/max/mid depending on input
         %Either compensates for coarse directly, or outputs calculated coarse compensation
         checkConnection(obj)

         [obj,fineRow] = findAxisRow(obj,spatialAxis,'fine');
         [obj,coarseRow] = findAxisRow(obj,spatialAxis,'coarse');

         %Updates current information on the coarse and fine stage of this axis
         obj = getStageInfo(obj,[fineRow,coarseRow]);

         %Finds absolute target location based on minMaxMid input. For min and max, an additional 2% buffer is given to
         %prevent going over bounds particularly in a tolerance check
         switch minMaxMid
            case {'minimum','min','low'}
               fineTarget = obj.controllerInfo(fineRow).limits(1) + .02*obj.controllerInfo(fineRow).intrinsicRange;

            case {'maximum','max','high'}
               fineTarget = obj.controllerInfo(fineRow).limits(2) - .02*obj.controllerInfo(fineRow).intrinsicRange;

            case {'midpoint','mid','middle'}
               fineTarget = obj.controllerInfo(fineRow).midpoint;
         end

         %If the fine target is within 5% (based on range) of its current location, do not perform reset and output
         %0 for coarse compensation. Fine resets are only really useful if they move the stage significantly, so this
         %reduces redundant movements
         percentageOff = abs(fineTarget - obj.controllerInfo(fineRow).targetLocation) / obj.controllerInfo(fineRow).intrinsicRange;
         if percentageOff < .05
            printOut(obj,'Fine reset aborted. Fine location already within 5% of its target')
            if ~compensateForCoarse,    varargout{1} = 0;    end
            return
         end

         %Calculates how far the fine stage will be moving. Used to calculate coarse compensation
         relativeFineMovement = fineTarget - obj.controllerInfo(fineRow).targetLocation;

         %Moves the fine stage to calculated location
         obj = directMove(obj,spatialAxis,fineTarget,'fine');

         %If enabled, move coarse stage to compensate for fine movement. Otherwise, output how much coarse stage should
         %move by to do that compensation
         if compensateForCoarse
            obj = directMove(obj,spatialAxis,obj.controllerInfo(coarseRow).targetLocation - relativeFineMovement,'coarse');
         else
            varargout{1} = -relativeFineMovement;
         end

         %Checks tolerance if enabled
         obj = toleranceCheck(obj,spatialAxis);

      end

      function obj = toleranceCheck(obj,spatialAxis)
         %Checks if current location is within tolerance μm of target location
         %This is the only function that will change the errorCompensation field for controllerInfo
         %It is solely used to change the target of the fine stage such that the location is within tolerance after
         %moving to what should be the target area

         %If set to not check tolerance or tolerance is 0, end function
         if ~obj.checkTolerance || (obj.tolerance == 0 && obj.absoluteTolerance) ||...
                 (obj.toleranceStandardDeviations == 0 && ~obj.absoluteTolerance)
            return
         end

         try
            %Works if only 1 axis per spatial axis (no grain)
            [obj,infoRows] = findAxisRow(obj,spatialAxis);
         catch
            %Works for fine and coarse grain for spatial axes
            [obj,infoRows] = findAxisRow(obj,spatialAxis,["coarse","fine"]);
         end         

         %Finds tolerance based on either absolute number or number of standard deviations given for each axis
         if ~isempty(nonzeros(obj.toleranceStandardDeviations))
            totalTolerance = 0;
            for ii = infoRows
               totalTolerance = totalTolerance + (obj.toleranceStandardDeviations*obj.controllerInfo(ii).locationDeviation);
            end
         elseif ~isempty(nonzeros(obj.absoluteTolerance))
            totalTolerance = obj.absoluteTolerance;
         else
            error('Either absoluteTolerance or toleranceStandardDeviations must be nonzero')
         end

         loopCounter = 0;
         while true
            loopCounter = loopCounter + 1;            

            targetLocation = 0;
            trueLocation = 0;
            for ii = infoRows
               targetLocation = targetLocation + obj.controllerInfo(ii).targetLocation;
               trueLocation = trueLocation + obj.controllerInfo(ii).location;
            end

            if abs(trueLocation - targetLocation) < totalTolerance
                fprintf('tolerance loops used: %d\n',loopCounter)
               return
            end

            %Every 50 ms, add compensation to finest stage based on difference between true and target
            if mod(loopCounter,50) == 0
               obj.controllerInfo(infoRows(end)).errorCompensation = obj.controllerInfo(infoRows(end)).errorCompensation + (trueLocation - targetLocation);
            end

            %Every 10 ms, jostle stage
            if mod(loopCounter,10) == 0
               oldIgnoreWait = obj.ignoreWait;
               obj.ignoreWait = true; %Disable wait for jostling
               for ii = infoRows
                  %Moves stage 1 nm then back again after 1 ms
                  obj = directMove(obj,spatialAxis,obj.controllerInfo(ii).targetLocation + .001,obj.controllerInfo(ii).grain);
                  pause(.01)
                  obj = directMove(obj,spatialAxis,obj.controllerInfo(ii).targetLocation,obj.controllerInfo(ii).grain);
               end
               obj.ignoreWait = oldIgnoreWait; %Set back to previous value
            end

            if loopCounter > 100 %Hard cap of 1 second
               error('Could not get %s axis within tolerance',spatialAxis)
            end

            %Wait 1 ms on failed tolerance check
            pause(.001)

         end
      end

      function [obj,varargout] = findLocationDeviance(obj,spatialAxis,varargin)
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
            [obj,axisRow] = findAxisRow(obj,spatialAxis,varargin{2});
         else
            [obj,axisRow] = findAxisRow(obj,spatialAxis);
         end

         locationDeviance = zeros(1,nReps); %Preallocation

         %Repeatedly query stage location and compare to target location
         tic
         for ii = 1:nReps
            obj = getStageInfo(obj,axisRow);
            locationDeviance(ii) = obj.controllerInfo(axisRow).location - obj.controllerInfo(axisRow).targetLocation;
         end
         %Outputs average time per data point as 3rd optional output
         varargout{3} = toc/nReps;

         %Get mean location 2nd optional output
         varargout{2} = mean(locationDeviance);

         %Output list of location deviations as 1st optional output
         varargout{1} = locationDeviance;

         %Sets location deviation for that axis to the found standard deviation
         obj.controllerInfo(axisRow).locationDeviation = std(locationDeviance);
      end

      function [obj,axisRows] = findAxisRow(obj,spatialAxis,varargin)
         %Finds the row in controllerInfo corresponding to the spatial axis name
         %If multiple rows exist, use 3rd argument to determine order of output

         %Determine the correct axis to move
         allSpatialAxes = strcmpi(spatialAxis,{obj.controllerInfo.axis});

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
            grainRow = strcmpi(grainStrings(ii),{obj.controllerInfo.grain});
            grainRow = find(grainRow & allSpatialAxes);
            if numel(grainRow) > 1
               error('2 connections exist for %s %s. Only 1 connection per axis/grain combination allowed',grainStrings(ii),spatialAxis)
            end
            axisRows(ii) = grainRow;
         end

      end
   end
end