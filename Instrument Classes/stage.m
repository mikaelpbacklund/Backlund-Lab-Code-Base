classdef stage < instrumentType
   % properties (Constant)
   %    defaults = struct('ignoreWait',false,'tolerance',.05,'pauseTime',.05,...
   %        'resetToMidpoint',true,'maxRecord',1000,'maxConnectionAttempts',3) 
   % end
   properties
      ignoreWait
      tolerance
      pauseTime
      resetToMidpoint %If true, fine axis resets to midpoint. If false, it resets to max/min depending on movement direction
      maxRecord
      controllerInfo      
      maxConnectionAttempts
      pathObject
      SNList
      handshake
      spatialAxes
      axisSum
      locationsRecord
   end
   
   
   
   methods
      %Methods from PI can be found in their software package that must be
      %downloaded to programfiles
      function h = stage(configFileName)

          if nargin < 1
              error('Config file name required as input')
          end
          
         addpath(getenv('PI_MATLAB_DRIVER'))

         %Loads config file and checks relevant field names
         configFields = {'controllerInfo','defaults'};
         commandFields = {};
         numericalFields = {};      
         h = loadConfig(h,configFileName,configFields,commandFields,numericalFields);

         %Set identifier as given name
         h.identifier = configFileName;
      end
      
      function h = connect(h)
         if h.connected
            warning('Stage is already connected')
            return
         end
         
         %Checks defaults of the following settings then
         %assigns them to corresponding properties
         s = checkSettings(h,fieldnames(h.defaults));
         h = instrumentType.overrideStruct(h,s);

         nfails = 0;
         while true
            h.pathObject = PI_GCS_Controller;
            h.SNList = EnumerateUSB(h.pathObject);
            SNnumbers = cellfun(@(a)findSN(a),h.SNList,'UniformOutput',false);
            typeList = cellfun(@(a)a(4:8),h.SNList,'UniformOutput',false);
            
            for jj = 1:numel(h.controllerInfo)
               for kk = 1:numel(typeList)
                  if strcmpi(h.controllerInfo(jj).model,typeList{kk})
                     h.controllerInfo(jj).serialNumber = SNnumbers{kk};
                  end
               end
            end
            currentControllerInfo{nfails+1} = h.controllerInfo;
            
            %Will give an error if connection fails
            try
                if ~isfield(h.controllerInfo,'serialNumber') || any(isempty({h.controllerInfo.serialNumber}))
                    error('Incomplete serial number information')
                end
                uniqueControllers = unique({h.controllerInfo.serialNumber});
                serialNumbers = cellfun(@(x)str2double(x),{h.controllerInfo.serialNumber},'UniformOutput',false);
                serialNumbers = cell2mat(serialNumbers);
               %For each unique serial number, connect to that controller
               %then match the serial number to the axes in controllerInfo
               for jj = 1:numel(uniqueControllers)
                  h.handshake{jj} = ConnectUSB(h.pathObject,(uniqueControllers{jj}));
                  matchingSN = find(serialNumbers == str2double(uniqueControllers{jj}));
                  for kk = 1:numel(matchingSN)
                    h.controllerInfo(matchingSN(kk)).handshakeNumber = jj;
                  end                  
               end
               break
            catch ME
                nfails = nfails+1;
                if ~isempty(h.handshake)
                   for jj = 1:numel(h.handshake)
                      h.handshake{jj}.CloseConnection
                   end
                   h.handshake = [];
                end
                if nfails >= h.maxConnectionAttempts
                    warning('Not all specified stage controllers were connected. Last error:')
                    assignin("base","totalcontrollerinfo",currentControllerInfo)
                    rethrow(ME)
                end
                warning('Not all specified stage controllers were connected (%d times). Retrying...',nfails)
                pause(1)
                
                continue
            end            
         end

         uniqueAxes = unique({h.controllerInfo.axis});
         h.axisSum = cell(numel(uniqueAxes),2);
         h.axisSum(:,1) = uniqueAxes;
         
         h.connected = true;
         h.identifier = 'stage';
         
         %Turn on all axes
         for ii = 1:numel(h.controllerInfo)
            h = toggleAxis(h,ii,'on');    
         end

          function  PISerialNumber = findSN(identificationString)
              SNLocation = strfind(identificationString,' SN ');
              PISerialNumber = identificationString(SNLocation+4:end-1);
          end

      end
      
      function h = toggleAxis(h,infoRow,toggleStatus)
         if strcmpi(instrumentType.discernOnOff(toggleStatus),'off')
            h.handshake{h.controllerInfo(infoRow).handshakeNumber}.Destroy
            return
         end
         
         %Turns on given axis. Also acquires its limits and current
         %position
         currentInfo = h.controllerInfo(infoRow);
         
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
         
         %Gets current information regarding this axis
         h = getStageInfo(h,infoRow);

         %Sets target location to current location
         h.controllerInfo(infoRow).targetLocation = h.controllerInfo(infoRow).location;
      end
      
      function h = disconnect(h)
          if ~h.connected
              return
          end
          if ~isempty(h.locationsRecord)
              h.locationsRecord = [];
          end
         if ~isempty(h.handshake)
            for ii = 1:size(h.handshake,1)
               h.handshake{ii}.Destroy
            end
            h.handshake = [];
         end       
         h.pathObject = [];
         h.connected = false;
      end
      
      function h = getStageInfo(h,axisRows)
         checkConnection(h)
         
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
            if h.maxRecord < 100
               h.locationsRecord(1:end-1,:) = [];
            else
               h.locationsRecord(1:100,:) = [];
            end
         end
         
         for ii = 1:size(h.axisSum,1)
            spatialAxis = h.axisSum{ii,1};
            designatedAxes = cellfun(@(a)strcmpi(spatialAxis,a(end)),{h.controllerInfo.axis});
            h.axisSum{ii,2} = sum(cell2mat({h.controllerInfo(designatedAxes).location}));
         end
      end
      
      function h = directMove(h,axisName,newTarget,varargin)
         %newTarget is desired absolute position

         checkConnection(h)
         
         %Determine the correct axis to move
         axisRow = strcmpi(axisName,{h.controllerInfo.axis});
         
         %If multiple connections exist with that axis name, check for
         %matching grain (coarse/fine)
         if sum(axisRow) > 1
            if sum(axisRow) > 2
               error('More than 2 connections exist for %s. This class was developed for using a maximum of 2 per axis',axisName)
            end
            if nargin < 4
               error('Multiple connections exist for %s but no designation of grain (coarse/fine) was given',axisName)
            end
            grainRow = strcmpi(varargin{1},{h.controllerInfo.grain});
            axisRow = grainRow & axisRow;
            if sum(axisRow) > 1
               error('2 connections exist for %s %s. Only 1 connection per axis/grain allowed',varargin{1},axisName)
            end
         end
         
         %Get shorthand for use later
         currentInfo = h.controllerInfo(axisRow);
         handshakeRow = currentInfo.handshakeNumber;

         h.controllerInfo(axisRow).targetLocation = newTarget;
         
         %Conversion to correct units
         newTarget = newTarget / currentInfo.conversionFactor;

         if currentInfo.invertLocation
             newTarget = -newTarget;
         end
         
         h.handshake{handshakeRow} .MOV(currentInfo.internalAxisNumber,newTarget); 
         
         if ~h.ignoreWait
            pause(h.pauseTime)
         end
         
         n = 0;
         while true
            %If ignore wait is on, do not wait for reported finished movement
            if h.ignoreWait
               break
            end
            
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
         
         h = getStageInfo(h,find(axisRow));         
      end

      function h = relativeMove(h,spatialAxis,targetMovement,varargin)
         checkConnection(h)

         if nargin > 3
             checkTolerance = varargin{1};
         else
             checkTolerance = true;
         end
         
         %Get information about what connections should be used
         spatialStages = strcmpi(spatialAxis,{h.controllerInfo.axis});
         fineRow = find(spatialStages & strcmpi('fine',{h.controllerInfo.grain}));
         coarseRow = find(spatialStages & strcmpi('coarse',{h.controllerInfo.grain}));
         sumRow = strcmpi(spatialAxis,h.axisSum(:,1));
         
         %If the movement is positive, determine if this movement would be outside
         %the high bound while if it is negative, do the same for the low bound
         inPositiveBound = targetMovement + h.controllerInfo(fineRow).location <= h.controllerInfo(fineRow).limits(2);
         inNegativeBound = targetMovement + h.controllerInfo(fineRow).location >= h.controllerInfo(fineRow).limits(1);
         
         if targetMovement == 0
            %Do nothing
            
         elseif (targetMovement > 0 && inPositiveBound) || (targetMovement < 0 && inNegativeBound)            
            %If target movement is positive, check the positive bound and
            %vice versa for negative

            %Conversion to absolute target location from relative
            absoluteTarget = targetMovement + h.axisSum{sumRow,2};            
            
            %If target is not outside of fine bounds, enact move on fine controller
            h = directMove(h,spatialAxis,absoluteTarget - h.controllerInfo(coarseRow).location,'fine');
            
            %Displays movement in command window            
            printOut(h,sprintf("Fine %s moved %g μm to %g; Axis total: %g",...
               spatialAxis,targetMovement,h.controllerInfo(fineRow).location,h.axisSum{sumRow,2}))

            if checkTolerance
            %Checks if current location is within tolerance of the absolute target
            h = toleranceCheck(h,spatialAxis,absoluteTarget);
            end
            
         else
            %If target is outside of fine bounds, reset fine to midpoint, move coarse
            %to desired location, then tune using fine
            
            %Stores absolute target for use in tolerance check
            absoluteTarget = targetMovement + h.axisSum{sumRow,2};
            storedFineLocation = h.controllerInfo(fineRow).location;
            
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

            %Ensures coarse stage does not overshoot boundary
            if targetMovement + h.controllerInfo(coarseRow).location > h.controllerInfo(coarseRow).limits(2) ...
                  || targetMovement + h.controllerInfo(coarseRow).location < h.controllerInfo(coarseRow).limits(1)
               error('Coarse %s stage boundary reached\n',spatialAxis)
            end

            %Reset fine axis and modify coarse movement to account for this
            %reset
            h = fineReset(h,spatialAxis,resetLocation);
            h = directMove(h,spatialAxis,absoluteTarget - h.controllerInfo(fineRow).location,'coarse');
            storedFineLocation = h.controllerInfo(fineRow).location - storedFineLocation;            

            %Displays movement in command window
            printOut(h,sprintf("Coarse %s moved %g μm to %g; Fine %s moved %g μm to %g ; Axis total: %g",...
               spatialAxis,targetMovement,h.controllerInfo(coarseRow).location,...
               spatialAxis,storedFineLocation,h.controllerInfo(fineRow).location,h.axisSum{sumRow,2}))
            
            if checkTolerance
            %Checks if current location is within tolerance of the absolute target
            h = toleranceCheck(h,spatialAxis,absoluteTarget);  
            end
         end
         
      end
      
      function h = absoluteMove(h,spatialAxis,targetLocation,varargin)
         checkConnection(h)
         
         if nargin > 3
             checkTolerance = varargin{1};
         else
             checkTolerance = true;
         end
         
         %Find the relative distance between target input and current sum
         sumRow = strcmpi(spatialAxis,h.axisSum(:,1));
         relativeDifference = targetLocation - h.axisSum{sumRow,2};
         
         %Uses relative move code to circumvent copy-pasting similar code here
         h = relativeMove(h,spatialAxis,relativeDifference,checkTolerance);
      end
      
      function [h,varargout] = fineReset(h,spatialAxis,minMaxMid,varargin)
         checkConnection(h)
         
         %Gets the corresponding rows for fine/coarse/sum 
         spatialStages = strcmpi(spatialAxis,{h.controllerInfo.axis});
         fineRow = find(spatialStages & strcmpi('fine',{h.controllerInfo.grain}));
         coarseRow = find(spatialStages & strcmpi('coarse',{h.controllerInfo.grain}));
         sumRow = strcmpi(spatialAxis,h.axisSum(:,1));
         
         %Updates current information on the coarse and fine stage of this
         %axis
         h = getStageInfo(h,[fineRow,coarseRow]);   
         
         %Check if fine stage is within 5% of what the target would be***
                  
         %Finds the absolute target for the fine movement based on input. For
         %minimum and maximum, an additional 2% buffer is given to prevent violating
         %limit when performing tolerance check
         switch minMaxMid
            case {'minimum','min','low'}               
               fineTarget = h.controllerInfo(fineRow).limits(1) + .02*h.controllerInfo(fineRow).intrinsicRange;
               
            case {'maximum','max','high'}
               fineTarget = h.controllerInfo(fineRow).limits(2) - .02*h.controllerInfo(fineRow).intrinsicRange;
               
            case {'midpoint','mid','middle'}
               fineTarget = h.controllerInfo(fineRow).midpoint;
               
         end
         
         %If the fine target is within 5% of its current location do not
         %complete the reset. It is assumed that fine resets are not useful
         %unless they actually move the fine stage by a significant amount,
         %so this prevents useless movements in the case only the coarse
         %stage is used for movement
         percentageOff = (fineTarget - h.controllerInfo(fineRow).location) / h.controllerInfo(fineRow).intrinsicRange;
         if percentageOff < .05 && percentageOff > -.05
            printOut(h,'Fine reset aborted. Fine location already within 5% of its target')
            if nargin > 3
                varargout{1} = varargin{1};
            end
            return
         end         
         
         %Records the current location of the sum of the stage positions
         oldLocation = h.axisSum{sumRow,2};
         
         %Moves the fine stage by calculated amount
         h = directMove(h,spatialAxis,fineTarget,'fine');
         
         if nargin == 3 
            %Moves coarse stage to compensate            
            h = directMove(h,spatialAxis,h.controllerInfo(coarseRow).targetLocation-fineTarget,'coarse');
            h = toleranceCheck(h,spatialAxis,oldLocation);%Immediate tolerance check
         else
            %Subtracts fine movement from input target location to be used
            %for coarse movement later
            varargout{1} = varargin{1} - fineTarget;
            %Tolerance checked later
         end      
      end
      
      function h = toleranceCheck(h,spatialAxis,targetLocation)
         %To fix: work with new absolute target location rather than relative movements

         % %Checks the current axis total location and continually adjusts
         % %fine stage for that axis until the location is within the
         % %tolerance value of the given target location
         % 
         % checkConnection(h)
         % 
         % %Gets the corresponding rows for fine/coarse/sum 
         % spatialStages = strcmpi(spatialAxis,{h.controllerInfo.axis});
         % fineRow = find(spatialStages & strcmpi('fine',{h.controllerInfo.grain}));
         % coarseRow = find(spatialStages & strcmpi('coarse',{h.controllerInfo.grain}));
         % sumRow = strcmpi(spatialAxis,h.axisSum(:,1));
         % 
         % %Sets attempt counts to 0 and stores old pause information
         % totalTries = 0;
         % currentTries = 0;
         % oldPauseTime = h.pauseTime;
         % oldIgnoreWait = h.ignoreWait;
         % 
         % while true %Continue checking location then moving until it is within tolerance
         %    totalTries = totalTries + 1;
         %    currentTries = currentTries + 1;
         % 
         %    %Cutoff in the case tolerance cannot be reached for some reason
         %    if totalTries > 20
         %       error('Tolerance unable to be reached for %s axis',spatialAxis)
         %    end
         % 
         %    %If there have been 3 tries without success, enable stage
         %    %waiting (if disabled) or increase the pause time slightly. The
         %    %idea here is to give the stage more time to settle in between
         %    %movement commands to prevent jittering
         %    if currentTries > 3
         %       if h.ignoreWait
         %          h.ignoreWait = false;
         %          printOut(h,'Temporarily enabling stage wait')
         %       else
         %          printOut(h,['Tolerance not reached after 3 attempts, temporarily adding ' ...
         %             '.01 seconds to pause time'])
         %          h.pauseTime = h.pauseTime + .01;
         %       end               
         %       currentTries = 1;
         %    end
         % 
         %    %Finds and stores the current position for the fine and coarse stages
         %    h = getStageInfo(h,[fineRow,coarseRow]);
         % 
         %    %Calculates how far the current position is from the target
         %    distanceError = targetLocation - h.axisSum{sumRow,2};
         % 
         %    %If the error is less than the tolerance, end the while loop, otherwise
         %    %move the stage to the target using the fine stage
         %    %Theoretically, this could cause the fine stage to hit its
         %    %bounds but this is very unlikely with normal operation
         %    if distanceError > - h.tolerance && distanceError < h.tolerance
         %        if totalTries == 1
         %            printOut(h,'Tolerance immediately achieved')
         %        elseif totalTries == 2
         %            printOut(h,'Tolerance achieved after 1 try')
         %        else
         %            printOut(h,sprintf('Tolerance achieved after %d tries',totalTries-1))
         %        end                
         %       break
         %    else
         %       h = directMove(h,spatialAxis,distanceError,'fine');
         %    end
         %
         % end
         % 
         % %Sets pause conditions to what they were before tolerance check
         % h.ignoreWait = oldIgnoreWait;
         % h.pauseTime = oldPauseTime;
         % 
         % printOut(h,sprintf('%s axis sum after tolerance check: %g',spatialAxis,...
         %     h.axisSum{sumRow,2}))
      end
      
      function [h,locationDeviance] = findLocationDeviance(h,axisName,varargin)
          if nargin > 2
              nReps = varargin{1};
          else
              nReps = 10;
          end

          spatialStages = strcmpi(axisName,{h.controllerInfo.axis});
          fineRow = find(spatialStages & strcmpi('fine',{h.controllerInfo.grain}));

          locationDeviance = zeros(1,nReps);

          for ii = 1:nReps              
              h = getStageInfo(h,fineRow);
              locationDeviance(ii) = h.controllerInfo(fineRow).location - h.controllerInfo(fineRow).targetLocation;
          end
      end
   end

end