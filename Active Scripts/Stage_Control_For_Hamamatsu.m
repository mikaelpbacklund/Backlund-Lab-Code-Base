%Edit params to desired scan
%Press run (or type Stage_Control_For_Hamamatsu in the console)
%If you get an error, just rerun the script. If this doesn't work, restart matlab
%Type 1 when prompted to start scan

%% Console commands
% ex.PIstage = absoluteMove(ex.PIstage,spatialAxis,targetLocation);
% ex.PIstage = relativeMove(ex.PIstage,spatialAxis,targetMovement);
%axisSumLocations = ex.PIstage.axisSum;
%scanInfo = ex.scan;
%Coarse x/y/z then fine x/y/z below
%axisIndividualLocations = ex.PIstage.controllerInfo.location;

%% Params
pauseTime = 1;%Time (in seconds) between stage movements
%Axes bounds for scan. [0 0] or [] for no scan on that axis
xAxisBounds = [73.0327 73.0727];
yAxisBounds = [95.5393 95.5793];
zAxisBounds = [0 0];
%Step size in microns
xAxisStepSize = .002;
yAxisStepSize = .002;
zAxisStepSize = 1;
%Number of steps. Overrides step size if given. Leave as 0 or [] to not use
xAxisNSteps = [];
yAxisNSteps = [];
zAxisNSteps = [];

%% Backend
pauseDuration = seconds(pauseTime);%Conversion to duration from double

%Creates experiment and stage objects if not already made
if ~exist('ex','var')
   ex = experiment;
end
if isempty(ex.PIstage) || ~ex.PIstage.connected
    ex.PIstage = stage('PI_stage');
    ex.PIstage = connect(ex.PIstage);
end

%Deletes any pre-existing scan
ex.scan = [];

%Adds x,y, and z scans if bounds are given
ex = addStageScan(ex,xAxisBounds,xAxisNSteps,xAxisStepSize,'x');
ex = addStageScan(ex,yAxisBounds,yAxisNSteps,yAxisStepSize,'y');
ex = addStageScan(ex,zAxisBounds,zAxisNSteps,zAxisStepSize,'z');

%Gets information to display to user
loopCounter = 0;
totalNScans = prod([ex.scan.nSteps]);
scanStartInfo(totalNScans,pauseTime,1,0)
cont = checkContinue(10);
if ~cont
    return
end

%Reset current scan each iteration
   ex = resetScan(ex);
   while ~all(cell2mat(ex.odometer) == [ex.scan.nSteps]) %While odometer does not match max number of steps
       startTime = datetime;
       loopCounter = loopCounter + 1;
       %Increment the odometer and set the instrument to the next value
       %'none' argument indicates do not take data
      ex = takeNextDataPoint(ex,'none');     
      while true %This while loop checks to see if elapsed duration exceeds pause duration setting
          if (datetime - startTime) >= pauseDuration
            break
          end
          pause(.001)
      end
      fprintf('%d/%d complete (%.2f seconds)\n',loopCounter,totalNScans,seconds(datetime-startTime))
   end


function h = addStageScan(h,bounds,nSteps,stepSize,axisParam)
%Adds scan in the particular way desired for this script
if isempty(bounds) || all(bounds == [0 0])
    return
end
if ~isempty(nSteps) && nSteps ~= 0 
    scan.nSteps = nSteps;
else
    scan.stepSize = stepSize;
end
scan.bounds = bounds;
scan.parameter = axisParam;
scan.identifier = 'PI Stage';%Which instrument is being scanned
scan.notes = 'Stage Scan for Hamamatsu Imaging';%Internal notes for scan
h = addScans(h,scan);
end
