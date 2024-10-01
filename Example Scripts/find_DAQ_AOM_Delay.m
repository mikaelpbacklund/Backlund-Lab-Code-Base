%Finds the optimal delay between AOM and DAQ
%Runs a Rabi using the current RF frequency with a set duration of rabiDuration

%Default ODMR script example

%% User Inputs
RFResonance = 2.87;
RabiTauDuration = 50;%max contrast tau duration
initialDelayGuess = 400; %how much sooner AOM must trigger before DAQ (negative is flipped)
coarseEstimationStepSize = 50;%ns
coarseEstimationNSteps = 9;%odd number
fineEstimationStepSize = 10;
fineEstimationNSteps = 9;%odd number
fineEstimationNIterations = 5;

collectionChannel = 'analog';
collectionDuration = 1000;
sequenceTimePerDataPoint = 3;%Before factoring in forced delay and other pauses
timeoutDuration = 10;
forcedDelayTime = .125;
nDataPointDeviationTolerance = .0001;
scanNotes = 'Rabi for Estimating DAQ/AOM Delay';

%% Backend

%This warning *should* be suppressed in the DAQ code but isn't for an unknown reason. This is not related to my code but
%rather the data acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%Creates experiment object if none exist
if ~exist('ex','var')
   ex = experiment;
end

%If there is no pulseBlaster object, create a new one with the config file "pulse_blaster_config"
if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('PB');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end

%If there is no RF_generator object, create a new one with the config file "SRS_RF"
%This is the "normal" RF generator that our lab uses, other specialty RF generators have their own configs
if isempty(ex.SRS_RF)
   ex.SRS_RF = RF_generator('SRS_RF');
   ex.SRS_RF = connect(ex.SRS_RF);
end

%If there is no DAQ_controller object, create a new one with the config file "NI_DAQ_config"
if isempty(ex.DAQ)
   ex.DAQ = DAQ_controller('NI_DAQ');
   ex.DAQ = connect(ex.DAQ);
end

%Turns RF on, disables modulation, and sets amplitude to 10 dBm
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = RFamplitude;
ex.SRS_RF.frequency = RFResonance;

%Temporarily disables taking data, differentiates signal and reference (to get contrast), and sets data channel to
%counter
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = collectionChannel;

%Sets loops for entire sequence to "on". Deletes previous sequence if any existed
ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

%First pulse is variable RF duration, second is data collection
%Second input is active channels, third is duration, fourth is notes
h = condensedAddPulse(h,{},RabiTauDuration,'τ without-RF time');%Scanned
h = condensedAddPulse(h,{'AOM','Data'},p.collectionDuration,'Reference Data collection');

h = condensedAddPulse(h,{'RF','Signal'},RabiTauDuration,'τ with-RF time');%Scanned
h = condensedAddPulse(h,{'AOM','Data','Signal'},p.collectionDuration,'Signal Data collection');

%See function for more detail. Modifies base sequence with necessary things to function properly
h = standardTemplateModifications(h,2500,7000,1000,initialDelayGuess);

%Changes number of loops to match desired time for each data point
ex.pulseBlaster.nTotalLoops = floor(sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = forcedDelayTime;

ex.maxFailedCollections = 10;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = nDataPointDeviationTolerance;

%Creates scan of AOM/DAQ duration. Cuts off scan if it would go to negative values, will flip AOM/DAQ entirely if needed
%Scan bounds and step size determined by coarse inputs
%Runs scan and creates quadratic fit to get max contrast
%Fit accuracy is relatively unimportant and is just used to determine if max contrast is within current range
%If estimated max value is not within current range, repeat using estimated max as new center value for scan
%If estimated max value is within current range, center on highest current value
%Doesn't center on estimated value as fit accuracy is likely poor
%Performs fine scan for nIterations using fine inputs
%Max contrast value is given as result

try
   %Changes scan
   ex.scan = [];
   scanInfo.parameter = 'duration';
   scanInfo.identifier = 'Pulse Blaster';
   scan.notes = scanNotes;
   scan.bounds = scanBounds;
   scan.stepSize = scanStepSize;
   ex = addScans(ex,scan);

   %Resets current data. [0,0] is for reference and signal counts
   ex = resetAllData(ex,[0,0]);

   avgData = zeros([ex.scan.nSteps 1]);

   if isCoarse
      nIterations = 1;
   else
      nIterations = fineEstimationNIterations;
   end

   compensationPulses = findPulses(h,'notes','AOM/DAQ delay compensation','matches');

   for ii = 1:nIterations

      %Reset current scan each iteration
      ex = resetScan(ex);

      iterationData = zeros([ex.scan.nSteps 1]);

      while ~all(ex.odometer == [ex.scan.nSteps]) %While odometer does not match max number of steps

         %Takes the next data point. This includes incrementing the odometer and setting the instrument to the next value
         ex = takeNextDataPoint(ex,'pulse sequence');

         %Transforms data to contrast for current iteration and average 
         currentData = mean(createDataMatrixWithIterations(ex,ex.odometer),2);
         currentData = (currentData(1)-currentData(2))/currentData(1);
         avgData(ex.odometer) = currentData;
         currentData = ex.data.values{ex.odometer,end};
         currentData = (currentData(1)-currentData(2))/currentData(1);
         iterationData(ex.odometer) = currentData;

         

      end

   end

catch ME
   stop(ex.DAQ.handshake)
   rethrow(ME)
end
stop(ex.DAQ.handshake)


