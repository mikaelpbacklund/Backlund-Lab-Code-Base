%Edit params to desired scan
%Press run (or type Hamamatsu_Scan in the console)
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
   %Outputs current standard deviation for each stage axis
   for ii = ["x","y","z"]
      [ex.PIstage,~,~,locStdDev] = findLocationDeviance(ex.PIstage,ii,100,'coarse');
      fprintf('Coarse %s axis location has a standard deviation of %.1f nm\n',locStdDev*1000)
      [ex.PIstage,~,locMean,locStdDev] = findLocationDeviance(ex.PIstage,ii,100,'fine');
      fprintf('Fine %s axis location has a standard deviation of %.1f nm\n',locStdDev*1000)
   end
end
if isempty(ex.hamm) || ~ex.hamm.connected
   ex.hamm = cam('camera');
   ex.hamm = connect(ex.hamm);
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


%% Running Scan
%Creates form data will be in
%Detemines number of rows by number of bounds in camera and whether an additional full image will be added
%1 column if only average image, 2 if frame stacks are included
nOutputs = getNumberOfImageOutputs(ex.hamm,[2304 2304]);
if ex.hamm.outputFrameStack
   blankData = cell(nOutputs,2);
elseif nOutputs == 1
   blankData = zeros(2304);
else
   blankData = cell(nOutputs,1);
end

%Resets current data based on blank data
ex = resetAllData(ex,blankData);

currentMeanFig = figure(1);
currentMeanAx = axes(currentMeanFig);

for ii = 1:nIterations

   %Reset current scan each iteration
   ex = resetScan(ex);

   while ~all(ex.odometer == [ex.scan.nSteps]) %While odometer does not match max number of steps
      loopCounter = loopCounter + 1;

      %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
      ex = takeNextDataPoint(ex,'scmos');

      %Plots most recently obtained averageImage
      currentIm = ex.data.values{ex.odometer,end};
      if isa(currentIm,'cell')
         currentIm = currentIm{1,1};
      end
      currentMeanIm = imagesc(currentMeanAx,currentIm);

      fprintf('%d/%d complete\n',loopCounter,totalNScans)

   end

   %Between each iteration, check for user input whether to continue scan
   %5 second timeout
   if ii ~= nIterations
      cont = checkContinue(timeoutDuration);
      if ~cont
         break
      end
      fprintf('Iteration %d complete',ii)
   end
end
fprintf('Scan complete\n')


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
