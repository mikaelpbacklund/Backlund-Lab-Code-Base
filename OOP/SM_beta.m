
%Loads instruments and their objects
if ~exist('ex','var')
   ex = experiment_beta;
end

if isempty(ex.PIstage)
   ex.PIstage = stage;
   ex.PIstage = connect(ex.PIstage,'PI_stage_config');
end

if isempty(ex.DDL)
   ex.DDL = kinesis_piezo;
   ex.DDL = connect(ex.DDL,'ddl_config');
end

if isempty(ex.hamm)
   ex.hamm = kinesis_piezo;
   ex.hamm = connect(ex.hamm,'hamm_cam_config');
end

%Gets the bounds for the images if none exist
if isempty(ex.hamm.bounds)   
   ex.hamm = boundSelector(ex.hamm);
end

%Minimizes image outputs to only the selected bounds' average images
ex.hamm.outputFrameStack = false;
ex.hamm.outputFullImage = false;

%Sets the number of frames obtained for each average image to 100
ex.hamm.framesPerTrigger = 100;

%Sets the voltage of the DDL
ex.DDL.voltage = 10;

%Deletes previous scan
ex.scan = [];

%Settings for scan to do
scan.bounds = [0 10];
scan.stepSize = .1;
scan.parameter = 'X';
scan.instrument = 'kinesis_piezo';
scan.notes = 'x scan';

%Adds scan using above settings
ex = addScans(ex,scan);

%Creates empty matrices in the shape for each set of bounds
ex = resetAllData(ex,generateBlankOutput(ex.hamm));

%Resets the scan to its starting point, putting the stage at its lower bound
ex = resetScan(ex);

%While odometer isn't at maximum
while ~all(ex.odometer == [ex.scan.nSteps])

   %Moves the stage then takes images according to settings
   ex = takeNextDataPoint(ex,'scmos');

   %For every set of bounds, display an image
   for ii = 1:numel(h.hamm.bounds)
      plotTitle = sprintf('Average Image of Bounds %d',ii);

      %The data is obtained from the current iteration (this script is only
      %designed for 1 iteration). It obtains it from the data point that
      %was most recently taken aka what the odometer reading is. It does
      %this for each of the cells saved which correspond to the different
      %images
      dataToPlot = ex.data.current{ex.odometer}{ii};
      ex = plotData(ex,dataToPlot,plotTitle);
   end

end

params.micronToPixel = .1;%Length/width of each pixel in microns
params.nFrames = 1000;
params.exposureTime = h.hamm.exposureTime;
params.highPass = 70;%Percentile to include for 1D gaussian
params.separationDistance = 1;%How far stage will move to create initial separation
params.gaussianRatio = 4;%How much larger one gaussian must be than the other to declare distance to be 0
ex = overlapAlgorithm(ex,'precision',params);





