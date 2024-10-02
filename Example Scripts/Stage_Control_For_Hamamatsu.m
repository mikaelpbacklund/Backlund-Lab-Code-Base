%% Params
pauseTime = .25;%Number of seconds to wait after each move
%Axes bounds for scan. [0 0] or [] for no scan on that axis
xAxisBounds = [0 0];
yAxisBounds = [0 0];
zAxisBounds = [0 0];
%Step size in microns
xAxisStepSize = 1;
yAxisStepSize = 1;
zAxisStepSize = 1;
%Number of steps. Overrides step size if given. Leave as 0 or [] to not use
xAxisNSteps = [];
yAxisNSteps = [];
zAxisNSteps = [];

%% Backend
if ~exist('ex','var')
   ex = experiment;
end

if isempty(ex.PIstage)
    ex.PIstage = stage('PI_stage');
    ex.PIstage = connect(ex.PIstage);
end

%Deletes any pre-existing scan
ex.scan = [];

%Adds x,y, and z scans if bounds are given
ex = addStageScan(ex,xAxisBounds,xAxisNSteps,xAxisStepSize,'x');
ex = addStageScan(ex,yAxisBounds,yAxisNSteps,yAxisStepSize,'y');
ex = addStageScan(ex,zAxisBounds,zAxisNSteps,zAxisStepSize,'z');

loopCounter = 0;
totalNScans = prod(ex.scan.nSteps);

%Reset current scan each iteration
   ex = resetScan(ex);
   while ~all(ex.odometer == [ex.scan.nSteps]) %While odometer does not match max number of steps
       loopCounter = loopCounter + 1;
       %Increment the odometer and set the instrument to the next value
       %'none' argument indicates do not take data
      ex = takeNextDataPoint(ex,'none');     
      pause(pauseTime)
      fprintf('%d/%d complete',loopCounter,totalNScans)
   end


function h = addStageScan(h,bounds,nSteps,stepSize,axisParam)

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
scan.identifier = 'PI stage';%Which instrument is being scanned
scan.notes = 'Stage Scan for Hamamatsu Imaging';%Internal notes for scan
h = addScans(h,scan);
end
